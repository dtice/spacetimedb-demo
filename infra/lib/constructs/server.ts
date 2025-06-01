import { RemovalPolicy, Duration, Stack } from 'aws-cdk-lib';
import {
    Vpc,
    SecurityGroup,
    Instance,
    InstanceType,
    InstanceClass,
    InstanceSize,
    CloudFormationInit,
    InitConfig,
    InitFile,
    InitCommand,
    UserData,
    MachineImage,
    AmazonLinuxCpuType,
    Peer,
    Port,
    KeyPair,
} from 'aws-cdk-lib/aws-ec2';
import {
    Role,
    ServicePrincipal,
    ManagedPolicy,
    PolicyDocument,
    PolicyStatement,
} from 'aws-cdk-lib/aws-iam';
import { Bucket, ObjectOwnership } from 'aws-cdk-lib/aws-s3';
import { Source, BucketDeployment } from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

interface ServerProps {
    vpc: Vpc;
    sshSecurityGroup: SecurityGroup;
    keypairName: string; // Keypair ID for SSH access
    logLevel: string;
    cpuType: AmazonLinuxCpuType;
    instanceSize: InstanceSize;
    instanceClass: InstanceClass;
}

export class ServerResources extends Construct {
    public instance: Instance;
    public instanceSecurityGroup: SecurityGroup;

    constructor(scope: Construct, id: string, props: ServerProps) {
        super(scope, id);

        // Create an Asset Bucket for the Instance.  Assets in this bucket will be downloaded to the EC2 during deployment
        const assetBucket = new Bucket(this, 'assetBucket', {
            publicReadAccess: false,
            removalPolicy: RemovalPolicy.DESTROY,
            objectOwnership: ObjectOwnership.BUCKET_OWNER_PREFERRED,
            autoDeleteObjects: true,
        });

        // Deploy the local assets to the Asset Bucket during the CDK deployment
        new BucketDeployment(this, 'assetBucketDeployment', {
            sources: [Source.asset('lib/resources/server/assets')],
            destinationBucket: assetBucket,
            retainOnDelete: false,
            exclude: ['**/node_modules/**', '**/dist/**'],
            memoryLimit: 512,
        });

        // Create a role for the EC2 instance to assume.  This role will allow the instance to put log events to CloudWatch Logs
        const serverRole = new Role(this, 'serverEc2Role', {
            assumedBy: new ServicePrincipal('ec2.amazonaws.com'),
            inlinePolicies: {
                ['RetentionPolicy']: new PolicyDocument({
                    statements: [
                        new PolicyStatement({
                            resources: ['*'],
                            actions: ['logs:PutRetentionPolicy'],
                        }),
                    ],
                }),
            },
            managedPolicies: [
                ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
                ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
            ],
        });

        // Grant the EC2 role access to the bucket
        assetBucket.grantReadWrite(serverRole);

        const userData = UserData.forLinux();

        // Add user data that is used to configure the EC2 instance
        userData.addCommands(
            'yum update -y',
            'curl -sL https://dl.yarnpkg.com/rpm/yarn.repo | sudo tee /etc/yum.repos.d/yarn.repo',
            'curl -sL https://rpm.nodesource.com/setup_18.x | sudo -E bash - ',
            'yum install -y amazon-cloudwatch-agent nodejs python3-pip zip unzip docker yarn',
            'sudo systemctl enable docker',
            'sudo systemctl start docker',
            'mkdir -p /home/spacetimedb',
            `aws s3 cp s3://${assetBucket.bucketName} /home/spacetimedb --recursive`,
            // Check and fix file permissions
            'ls -la /home/spacetimedb',
            // Execute setup script to install and configure the application
            'cd /home/spacetimedb',
            'sudo chmod 755 /home/spacetimedb/setup.sh',
            'sudo bash /home/spacetimedb/setup.sh > /home/spacetimedb/setup.log 2>&1',
            'echo "Setup script completed with exit code: $?"',
            'cat /home/spacetimedb/setup.log'
        );

        // Create a Security Group for the EC2 instance
        this.instanceSecurityGroup = new SecurityGroup(
            this,
            'ec2InstanceSecurityGroup',
            {
                vpc: props.vpc,
                description: 'Security Group for EC2 instance',
                allowAllOutbound: true
            },
        );

        // Allow HTTP and HTTPS access from anywhere
        this.instanceSecurityGroup.addIngressRule(Peer.anyIpv4(), Port.tcp(80), 'Allow HTTP');
        this.instanceSecurityGroup.addIngressRule(Peer.anyIpv4(), Port.tcp(443), 'Allow HTTPS');

        // Create the EC2 instance
        this.instance = new Instance(this, 'Instance', {
            vpc: props.vpc,
            instanceType: InstanceType.of(props.instanceClass, props.instanceSize),
            machineImage: MachineImage.latestAmazonLinux2023({
                cachedInContext: false,
                cpuType: props.cpuType,
            }),
            userData: userData,
            securityGroup: this.instanceSecurityGroup,
            keyPair: KeyPair.fromKeyPairName(this, 'EC2StackKeyPair', props.keypairName),
            init: CloudFormationInit.fromConfigSets({
                configSets: {
                    default: ['config'],
                },
                configs: {
                    config: new InitConfig([
                        InitFile.fromObject('/etc/config.json', {
                            // Use CloudformationInit to create an object on the EC2 instance
                            STACK_ID: Stack.of(this).artifactId,
                        }),
                        InitFile.fromFileInline(
                            // Use CloudformationInit to copy a file to the EC2 instance
                            '/tmp/amazon-cloudwatch-agent.json',
                            './lib/resources/server/config/amazon-cloudwatch-agent.json',
                        ),
                        // Create the config script directly rather than using a file
                        InitFile.fromString(
                            '/etc/config.sh',
                            '#!/bin/bash\n' +
                            '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/tmp/amazon-cloudwatch-agent.json\n'
                        ),
                        InitCommand.shellCommand('chmod +x /etc/config.sh'), // Make it executable
                        InitCommand.shellCommand('/bin/bash /etc/config.sh'), // Run it explicitly with bash
                    ]),
                },
            }),
            initOptions: {
                timeout: Duration.minutes(10),
                includeUrl: true,
                includeRole: true,
                printLog: true,
            },
            role: serverRole,
        });

        // Add the SSH Security Group to the EC2 instance
        this.instance.addSecurityGroup(props.sshSecurityGroup);
    }
}