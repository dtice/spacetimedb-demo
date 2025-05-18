import { Construct } from 'constructs';
import { BlockPublicAccess, Bucket, BucketEncryption, HttpMethods } from 'aws-cdk-lib/aws-s3';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';
import {
    Distribution,
    OriginRequestPolicy,
    CachePolicy,
    ViewerProtocolPolicy,
    ResponseHeadersPolicy,
    AllowedMethods,
    ResponseHeadersPolicyProps,
    HeadersFrameOption,
    HeadersReferrerPolicy,
} from 'aws-cdk-lib/aws-cloudfront';
import { S3BucketOrigin } from 'aws-cdk-lib/aws-cloudfront-origins';
import { Certificate } from 'aws-cdk-lib/aws-certificatemanager';

export interface GameBucketProps {
    bucketName: string;
    certificateArn: string;
}

export class GameResources extends Construct {
    public readonly bucket: Bucket;
    public readonly distribution: Distribution;

    constructor(scope: Construct, id: string, props: GameBucketProps) {
        super(scope, id);

        this.bucket = new Bucket(this, 'UnityGameBucket', {
            bucketName: props.bucketName,
            websiteIndexDocument: 'index.html',
            websiteErrorDocument: '404.html',
            encryption: BucketEncryption.S3_MANAGED,
            removalPolicy: RemovalPolicy.DESTROY, // NOT for production
            autoDeleteObjects: true, // NOT for production
            cors: [
                {
                    allowedMethods: [HttpMethods.GET],
                    allowedOrigins: ['*'],
                    allowedHeaders: ['*'],
                },
            ],
            blockPublicAccess: BlockPublicAccess.BLOCK_ACLS, // Block ACLs, but allow access via CloudFront
            publicReadAccess: false, // Only CloudFront can access
        });

        const origin = S3BucketOrigin.withOriginAccessControl(this.bucket);

        // Create a cache policy that includes Content-Encoding in the cache key
        const unityBrotliCachePolicy = new CachePolicy(this, 'UnityBrotliCachePolicy', {
            cachePolicyName: 'UnityBrotliCachePolicy',
            comment: 'Cache policy for Unity WebGL Brotli files',
            defaultTtl: Duration.days(1),
            minTtl: Duration.minutes(1),
            maxTtl: Duration.days(365),
            enableAcceptEncodingGzip: true,
            enableAcceptEncodingBrotli: true,
        });

        // Create a response headers policy for handling Brotli files
        const responseHeadersPolicy = new ResponseHeadersPolicy(this, 'UnityBrotliResponseHeadersPolicy', {
            responseHeadersPolicyName: 'UnityBrotliResponseHeadersPolicy',
            comment: 'Adds Content-Encoding: br header for .br files and CORS headers',
            corsBehavior: {
                accessControlAllowOrigins: ['*'],
                accessControlAllowMethods: ['GET', 'HEAD', 'OPTIONS'],
                accessControlAllowHeaders: ['*'],
                accessControlAllowCredentials: false,
                originOverride: true,
            },
        });

        const certificate = Certificate.fromCertificateArn(this, 'Certificate', props.certificateArn);

        this.distribution = new Distribution(this, 'UnityGameDistribution', {
            defaultBehavior: {
                origin,
                viewerProtocolPolicy: ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowedMethods: AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
                cachePolicy: unityBrotliCachePolicy,
                responseHeadersPolicy,

            },
            certificate,
            domainNames: ['ufo.dilltice.com'],
            defaultRootObject: 'index.html',
            errorResponses: [
                {
                    httpStatus: 404,
                    responseHttpStatus: 404,
                    responsePagePath: '/404.html',
                    ttl: Duration.minutes(5),
                },
            ],
        });
    }
}