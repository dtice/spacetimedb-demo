import { Stack, StackProps, CfnOutput } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { VPCResources } from './constructs/vpc';
import { ServerResources } from './constructs/server';
import {
  AmazonLinuxCpuType,
  Instance,
  InstanceClass,
  InstanceSize,
  SecurityGroup,
  Vpc,
  CfnEIP,
  CfnEIPAssociation
} from 'aws-cdk-lib/aws-ec2';

export interface EC2StackProps extends StackProps {
  logLevel: string;
  keypairName: string;
  cpuType: AmazonLinuxCpuType;
  instanceSize: InstanceSize;
  instanceClass: InstanceClass;
}

export class EC2Stack extends Stack {
  public readonly instance: Instance;
  public readonly vpc: Vpc;
  public readonly securityGroup: SecurityGroup;
  public readonly instanceSecurityGroup: SecurityGroup;
  public readonly elasticIp: CfnEIP;

  constructor(scope: Construct, id: string, props: EC2StackProps) {
    super(scope, id, props);

    const { logLevel, cpuType, instanceSize, instanceClass, keypairName } = props;

    // Create VPC and Security Group
    const vpcResources = new VPCResources(this, 'VPC');

    // Create EC2 Instance
    const serverResources = new ServerResources(this, 'EC2', {
      vpc: vpcResources.vpc,
      keypairName,
      sshSecurityGroup: vpcResources.sshSecurityGroup,
      logLevel: logLevel,
      cpuType: cpuType,
      instanceSize,
      instanceClass
    });

    this.vpc = vpcResources.vpc;
    this.securityGroup = vpcResources.sshSecurityGroup;
    this.instanceSecurityGroup = serverResources.instanceSecurityGroup;
    this.instance = serverResources.instance;

    // Create an Elastic IP and associate it with the EC2 instance
    this.elasticIp = new CfnEIP(this, 'ElasticIP', {
      domain: 'vpc',
    });

    // Associate the Elastic IP with the EC2 instance
    new CfnEIPAssociation(this, 'ElasticIPAssociation', {
      eip: this.elasticIp.ref,
      instanceId: this.instance.instanceId,
    });

    // SSM Command to start a session
    new CfnOutput(this, 'ssmCommand', {
      value: `aws ssm start-session --target ${serverResources.instance.instanceId}`,
    });

    // SSH Command to connect to the EC2 Instance
    new CfnOutput(this, 'sshCommand', {
      value: `ssh ec2-user@${serverResources.instance.instancePublicDnsName}`,
    });

    // Output the Elastic IP address
    new CfnOutput(this, 'InstanceElasticIP', {
      value: this.elasticIp.ref,
      description: 'Elastic IP address for the EC2 instance',
      exportName: 'EC2ElasticIP'
    });

    new CfnOutput(this, 'InstanceDnsName', {
      value: this.instance.instancePublicDnsName,
      exportName: 'EC2InstanceOptions'
    })
  }
}