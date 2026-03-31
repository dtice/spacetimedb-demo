@echo off
aws s3 --profile dilltice-dev sync unity/cows-n-ufos/Build s3://cows-n-ufos-game-assets --delete
aws cloudfront --profile dilltice-dev create-invalidation --distribution-id E13OCNOAUEF86T --paths "/*"