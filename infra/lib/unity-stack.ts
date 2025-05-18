import { Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { GameResources } from './constructs/game'; // Adjust the import path if needed

export interface UnityStackProps extends StackProps {
    bucketName: string;
    certificateArn: string;
}

export class UnityStack extends Stack {
    public readonly gameBucket: GameResources;

    constructor(scope: Construct, id: string, props: UnityStackProps) {
        super(scope, id, props);

        this.gameBucket = new GameResources(this, 'GameBucket', {
            bucketName: props.bucketName,
            certificateArn: props.certificateArn,
        });
    }
}