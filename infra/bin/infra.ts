#!/usr/bin/env node
import 'dotenv/config';
import { App } from 'aws-cdk-lib';
import { EC2Stack } from '../lib/ec2-stack';

const app = new App();

const devEnv = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

const stackProps = {
  logLevel: process.env.LOG_LEVEL || 'INFO',
  sshPubKey: process.env.SSH_PUB_KEY || ' ',
  cpuType: process.env.CPU_TYPE || 'ARM64',
  instanceSize: process.env.INSTANCE_SIZE || 'MICRO',
};

new EC2Stack(app, 'EC2Stack', {
  ...stackProps,
  env: devEnv,
  description: 'SpacetimeDB EC2 Stack',
});

app.synth();

