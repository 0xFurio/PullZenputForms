#!/bin/sh

echo creating GetFormSubmission role...

GetFormSubmissionRole=$(aws iam create-role --role-name GetFormSubmission-Role --assume-role-policy-document file://AssumeRolePolicy.json | jq -r ".Role.Arn")

sleep 8
echo done.
sleep 1
echo creating GetFormSubmission lambda...

GetFormSubmissionLambda=$(aws lambda create-function --function-name GetFormSubmission --zip-file fileb://build/GetFormSubmission.zip --runtime python3.7 --role $GetFormSubmissionRole --handler GetFormSubmission/GetFormSubmission.lambda_handler | jq -r ".FunctionArn")

echo done.
sleep 1
echo creating GetFormSubmission policy...

GetFormSubmissionPolicy=$(aws iam create-policy --policy-name GetFormSubmission-Policy --policy-document file://GetFormSubmissionPolicy.json | jq -r ".Policy.Arn")

echo done.
sleep 1
echo attaching role to policy...

aws iam attach-role-policy --role-name GetFormSubmission-Role --policy-arn $GetFormSubmissionPolicy

echo done.
sleep 1



echo creating SubmissionParse role...

SubmissionParseRole=$(aws iam create-role --role-name SubmissionParse-Role --assume-role-policy-document file://AssumeRolePolicy.json | jq -r ".Role.Arn")

echo done.
sleep 1
echo creating SubmissionParse layer...

SubmissionParseLayer=$(aws lambda publish-layer-version --layer-name SubmissionParseLayer --compatible-runtimes ruby2.7 --compatible-architectures x86_64 --zip-file fileb://layer.zip | jq -r ".LayerVersionArn")

echo done.
sleep 1
echo creating SubmissionParse lambda...

SubmissionParseLambda=$(aws lambda create-function --function-name SubmissionParse --zip-file fileb://build/SubmissionParse.zip --runtime ruby2.7 --role $SubmissionParseRole --handler SubmissionParse/lambda.handler --layers $SubmissionParseLayer | jq -r ".FunctionArn")

echo done.
sleep 1
echo creating SubmissionParse policy...

SubmissionParsePolicy=$(aws iam create-policy --policy-name SubmissionParse-Policy --policy-document file://SubmissionParsePolicy.json | jq -r ".Policy.Arn")

echo done.
sleep 1
echo attaching role to policy...

aws iam attach-role-policy --role-name SubmissionParse-Role --policy-arn $SubmissionParsePolicy

echo done.
sleep 1



echo creating dynamodb table...

aws dynamodb create-table --attribute-definitions AttributeName=FormID,AttributeType=S --table-name ProcessedForms --key-schema AttributeName=FormID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1

echo done.
sleep 1



echo creating sns topic...

ZenputSubmissionsTopic=$(aws sns create-topic --name ZenputSubmissions | jq -r ".TopicArn")

echo done.
sleep 1



echo "Enter Sendgrid API Key: "
read SendgridKey
sleep 1
echo "Enter Zenput API Key: "
read ZenputKey
sleep 1
echo updating lambda configurations...

aws lambda update-function-configuration --function-name GetFormSubmission --timeout 15 --environment Variables="{SENDGRID_API_KEY=$SendgridKey,ZENPUT_API_KEY=$ZenputKey,SNS_ARN=$ZenputSubmissionsTopic}"

sleep 1

aws lambda update-function-configuration --function-name SubmissionParse --timeout 15 --environment Variables="{SENDGRID_API_KEY=$SendgridKey,ZENPUT_API_KEY=$ZenputKey,OPTIONS=email}"

echo done.
sleep 1



echo creating dead letter queue...

DLQURL=$(aws sqs create-queue --queue-name ZenputSubmissionsDLQ | jq -r ".QueueUrl")

echo done.
sleep 1
echo processing queue attributes...

ZenputSubmissionsDLQ=$(aws sqs get-queue-attributes --queue-url $DLQURL --attribute-names QueueArn | jq -r ".Attributes.QueueArn")

echo done.
sleep 1
echo updating attributes configuration file...
echo "{" > attributes.json
echo "\"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$ZenputSubmissionsDLQ\\\",\\\"maxReceiveCount\\\":\\\"2\\\"}\"" >> attributes.json
echo "}" >> attributes.json
echo done.
sleep 1
echo creating main submission queue...

QueueURL=$(aws sqs create-queue --queue-name ZenputSubmissionsQueue --attributes file://attributes.json | jq -r ".QueueUrl")

echo done.
sleep 1
echo processing queue attributes...

ZenputSubmissionsQueue=$(aws sqs get-queue-attributes --queue-url $QueueURL --attribute-names QueueArn | jq -r ".Attributes.QueueArn")

echo done.
sleep 1
echo subscribing queue to topic...

aws sns subscribe --topic-arn $ZenputSubmissionsTopic --protocol sqs --notification-endpoint $ZenputSubmissionsQueue --attributes RawMessageDelivery=true

echo done.
sleep 1



echo creating event source mapping...

aws lambda create-event-source-mapping --function-name SubmissionParse --event-source-arn $ZenputSubmissionsQueue

echo done.
sleep 1
echo creating scheduled event...

GetFormSubmissionEvent=$(aws events put-rule --name GetFormSubmissionEvent --schedule-expression "rate(5 minutes)" | jq -r ".RuleArn")

echo done.
sleep 1
echo adding lambda permissions...

aws lambda add-permission --function-name GetFormSubmission --statement-id GetFormSubmissionEvent --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn $GetFormSubmissionEvent

echo done.
sleep 1
echo creating event target...

aws events put-targets --rule GetFormSubmissionEvent --targets 'Id'='1','Arn'=$GetFormSubmissionLambda

echo done.
sleep 1
echo creation complete.
