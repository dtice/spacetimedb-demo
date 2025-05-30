#!/usr/bin/env node
import 'dotenv/config';
import { App } from 'aws-cdk-lib';
import { EC2Stack } from '../lib/ec2-stack';
import { CloudFrontStack } from '../lib/cloudfront-stack';

const app = new App();

const devEnv = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

const ec2StackProps = {
  logLevel: process.env.LOG_LEVEL || 'INFO',
  sshPubKey: process.env.SSH_PUB_KEY || ' ',
  cpuType: process.env.CPU_TYPE || 'ARM64',
  instanceSize: process.env.INSTANCE_SIZE || 'MICRO',
};

const cloudfrontStackProps = {
  certificateArn: 'arn:aws:acm:us-east-1:730335480069:certificate/e76b4f1c-2521-46fd-9bb6-e90741839def',
}

const ec2Stack = new EC2Stack(app, 'EC2Stack', {
  ...ec2StackProps,
  env: devEnv,
  description: 'SpacetimeDB EC2 Stack',
});

new CloudFrontStack(app, 'CloudFrontStack', ec2Stack, {
  ...cloudfrontStackProps,
  env: devEnv,
  description: 'SpacetimeDB CloudFront Stack',
});

app.synth();

