import { Stack, StackProps, CfnOutput, Duration, RemovalPolicy } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { Peer, Port, PrefixList } from 'aws-cdk-lib/aws-ec2';
import { EC2Stack } from './ec2-stack';
import { HttpOrigin } from 'aws-cdk-lib/aws-cloudfront-origins';
import { AllowedMethods, CacheHeaderBehavior, CachePolicy, Distribution, OriginRequestPolicy, OriginSslPolicy, ViewerProtocolPolicy } from 'aws-cdk-lib/aws-cloudfront';
import { Certificate } from 'aws-cdk-lib/aws-certificatemanager';
import { BlockPublicAccess, Bucket, ObjectOwnership } from 'aws-cdk-lib/aws-s3';
import { Effect, PolicyStatement, ServicePrincipal } from 'aws-cdk-lib/aws-iam';

export interface CloudFrontStackProps extends StackProps {
    certificateArn: string;
}

export class CloudFrontStack extends Stack {
    constructor(scope: Construct, id: string, ec2Stack: EC2Stack, props: CloudFrontStackProps) {
        super(scope, id, props);

        const cfOriginFacing = PrefixList.fromLookup(this, "CloudFrontOriginFacing", {
            prefixListName: "com.amazonaws.global.cloudfront.origin-facing"
        });

        ec2Stack.securityGroup.addIngressRule(
            Peer.prefixList(cfOriginFacing.prefixListId),
            Port.tcp(80),
            'Allow HTTP access from CloudFront'
        );

        // Create an S3 bucket for CloudFront logs
        const logBucket = new Bucket(this, 'CloudFrontLogBucket', {
            blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
            removalPolicy: RemovalPolicy.RETAIN, // Keep logs even if stack is deleted
            autoDeleteObjects: false,
            objectOwnership: ObjectOwnership.BUCKET_OWNER_PREFERRED,
        });

        // Add bucket policy to allow CloudFront to write logs
        logBucket.addToResourcePolicy(new PolicyStatement({
            effect: Effect.ALLOW,
            principals: [new ServicePrincipal('logging.s3.amazonaws.com')],
            actions: ['s3:PutObject'],
            resources: [logBucket.arnForObjects('cloudfront-logs/*')]
        }));
        
        logBucket.addToResourcePolicy(new PolicyStatement({
            effect: Effect.ALLOW,
            principals: [new ServicePrincipal('delivery.logs.amazonaws.com')],
            actions: ['s3:PutObject'],
            resources: [logBucket.arnForObjects('cloudfront-logs/*')]
        }));

        // Get your existing certificate from ACM
        const certificate = Certificate.fromCertificateArn(this, 'Certificate', props.certificateArn);

        const distribution = new Distribution(this, 'Distribution', {
            defaultBehavior: {
                origin: new HttpOrigin(
                    ec2Stack.instance.instancePublicDnsName,
                    {
                        originSslProtocols: [OriginSslPolicy.TLS_V1_2],
                    }
                ),
                viewerProtocolPolicy: ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowedMethods: AllowedMethods.ALLOW_ALL,
                cachePolicy: CachePolicy.CACHING_DISABLED,
                originRequestPolicy: OriginRequestPolicy.ALL_VIEWER
            },
            certificate,
            domainNames: ['spacetime.dilltice.com'],
            enableLogging: true,
            logBucket: logBucket,
            logFilePrefix: 'cloudfront-logs/',
            logIncludesCookies: true
        });

        new CfnOutput(this, 'CloudFrontDomain', {
            value: distribution.distributionDomainName,
            exportName: 'CloudFrontDomain'
        });
    }
}