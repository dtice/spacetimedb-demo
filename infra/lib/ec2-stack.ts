import { Stack, StackProps, CfnOutput } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { VPCResources } from './constructs/vpc';
import { ServerResources } from './constructs/server';
import { EC2ExampleProps, envValidator } from './utils/env-validator';
import { Instance, SecurityGroup, Vpc } from 'aws-cdk-lib/aws-ec2';

export interface EC2StackProps extends StackProps, EC2ExampleProps {}

export class EC2Stack extends Stack {
  public readonly instance: Instance;
  public readonly vpc: Vpc;
  public readonly securityGroup: SecurityGroup;

  constructor(scope: Construct, id: string, props: EC2StackProps) {
    super(scope, id, props);

    const { logLevel, sshPubKey, cpuType, instanceSize } = props;

    // Validate environment variables
    envValidator(props);

    // Create VPC and Security Group
    const vpcResources = new VPCResources(this, 'VPC');

    // Create EC2 Instance
    const serverResources = new ServerResources(this, 'EC2', {
      vpc: vpcResources.vpc,
      sshSecurityGroup: vpcResources.sshSecurityGroup,
      logLevel: logLevel,
      sshPubKey: sshPubKey,
      cpuType: cpuType,
      instanceSize: instanceSize.toLowerCase(),
    });

    this.vpc = vpcResources.vpc;
    this.securityGroup = vpcResources.sshSecurityGroup;
    this.instance = serverResources.instance;

    // SSM Command to start a session
    new CfnOutput(this, 'ssmCommand', {
      value: `aws ssm start-session --target ${serverResources.instance.instanceId}`,
    });

    // SSH Command to connect to the EC2 Instance
    new CfnOutput(this, 'sshCommand', {
      value: `ssh ec2-user@${serverResources.instance.instancePublicDnsName}`,
    });

    new CfnOutput(this, 'InstanceDnsName', {
      value: this.instance.instancePublicDnsName,
      exportName: 'EC2InstanceOptions'
    })
  }
}