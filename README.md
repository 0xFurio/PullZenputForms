# Serverless Zapier Replacement
AWS architecture that periodically pulls new form submissions from the Zenput API and processes them.
<br><br/>
Can be built manually using steps below, or in CloudFormation using the provided template.
<br><br/>
# Setup
### 1. Create GetFormSubmission Lambda <br><br/>
Create an IAM role for the function to assume when invoked.
```
aws iam create-role --role-name GetFormSubmission-Role --assume-role-policy-document file://AssumeRolePolicy.json
```
\
Copy the ARN returned in the output and use it to create the function.
 - *Replace the placeholder ARN after the --role parameter.*

 - ***Take note of the GetFormSubmission ARN for later use.***
```
aws lambda create-function --function-name GetFormSubmission --zip-file fileb://build/GetFormSubmission.zip --runtime python3.7 --role GetFormSubmission-Role-ARN --handler GetFormSubmission/GetFormSubmission.lambda_handler
```
\
Create the IAM policy for the function.
```
aws iam create-policy --policy-name GetFormSubmission-Policy --policy-document file://GetFormSubmissionPolicy.json
```
\
Copy the ARN returned in the output and use it to attach the policy to the role.

- *Replace the placeholder ARN after the --policy-arn parameter.*
```
aws iam attach-role-policy --role-name GetFormSubmission-Role --policy-arn GetFormSubmission-Policy-ARN
```
<br><br/>
### 2. Create SubmissionParse Lambda <br><br/>

Create an IAM role for the function to assume when invoked.
```
aws iam create-role --role-name SubmissionParse-Role --assume-role-policy-document file://AssumeRolePolicy.json
```
\
Create a layer for the function.
```
aws lambda publish-layer-version --layer-name SubmissionParseLayer --compatible-runtimes ruby2.7 --compatible-architectures x86_64 --zip-file fileb://layer.zip
```
\
Copy the ARNs returned in both outputs and use them to create the function.

- *Replace the placeholder ARN after the --role parameter with the role ARN.*
- *Replace the placeholder ARN after the --layers parameter with the layer ARN.*
  - **This should be the ARN that includes the version number at the end.**

- ***Take note of the SubmissionParse ARN for later use.***
```
aws lambda create-function --function-name SubmissionParse --zip-file fileb://build/SubmissionParse.zip --runtime ruby2.7 --role SubmissionParse-Role-ARN --handler SubmissionParse/lambda.handler --layers SubmissionParseLayer-ARN:1
```
\
Create the IAM policy for the function.
```
aws iam create-policy --policy-name SubmissionParse-Policy --policy-document file://SubmissionParsePolicy.json
```
\
Copy the ARN returned in the output and use it to attach the policy to the role.

- *Replace the placeholder ARN after the --policy-arn parameter.*
```
aws iam attach-role-policy --role-name SubmissionParse-Role --policy-arn SubmissionParse-Policy-ARN
```
<br><br/>
### 3. Create DynamoDB Table <br><br/>

Create the DynamoDB table.
```
aws dynamodb create-table --attribute-definitions AttributeName=FormID,AttributeType=S --table-name ProcessedForms --key-schema AttributeName=FormID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1
```
<br><br/>
### 4. Create SNS Topic<br><br/>

Create the SNS topic.
- ***Take note of the topic ARN for later use.***
```
aws sns create-topic --name ZenputSubmissions
```
<br><br/>
### 5. Update Lambda Configurations <br><br/>

Update the GetFormSubmission function configuration.
- *Change the timeout value depending on how many forms are to be pulled. Timeout should be around 7.5x where x is the number of forms.*
- *Replace the placeholder keys after the SENDGRID_API_KEY and ZENPUT_API_KEY values with your API keys.*
- *Replace the placeholder ARN after the SNS_ARN value with the ZenputSubmissions ARN.*
```
aws lambda update-function-configuration --function-name GetFormSubmission --timeout 10 --environment Variables="{SENDGRID_API_KEY=YOURKEY,ZENPUT_API_KEY=YOURKEY,SNS_ARN=TOPICARN}"
```
\
Update the SubmissionParse function configuration.
- *Replace the placeholder keys after the SENDGRID_API_KEY and ZENPUT_API_KEY values with your API keys.*
- *Replace the SENDER_ADDRESS and ALERT_RECIPIENT values with the desired email addresses.*
```
aws lambda update-function-configuration --function-name SubmissionParse --timeout 10 --environment Variables="{SENDGRID_API_KEY=YOURKEY,ZENPUT_API_KEY=YOURKEY,OPTIONS=email,SENDER_ADDRESS=sender_email,ALERT_RECIPIENT=alert_email}"
```
<br><br/>
### 6. Create SQS Queue <br><br/>

Create the dead letter queue.
```
aws sqs create-queue --queue-name ZenputSubmissionsDLQ
```
\
Using the URL from the output, obtain the ARN.
- *Replace the placeholder URL after the --queue-url parameter.*
- ***Take note of the DLQ ARN for later use.***
```
aws sqs get-queue-attributes --queue-url ZenputSubmissionsDLQ-URL --attribute-names QueueArn
```
\
Open the attributes.json file in a text editor and replace the DLQ ARN. <br><br/>

Create the main queue.
```
aws sqs create-queue --queue-name ZenputSubmissionsQueue --attributes file://attributes.json
```
\
Using the URL from the output, obtain the ARN.
- *Replace the placeholder URL after the --queue-url parameter.*
- ***Take note of the Queue ARN for later use.***
```
aws sqs get-queue-attributes --queue-url ZenputSubmissionsQueue-URL --attribute-names QueueArn
```
\
Subscribe the main queue to the SNS topic.
- *Replace the placeholder ARN after the --topic-arn parameter with the Topic ARN.*
- *Replace the placeholder ARN after the --notification-endpoint parameter with the Queue ARN.*
```
aws sns subscribe --topic-arn ZenputSubmissions-ARN --protocol sqs --notification-endpoint ZenputSubmissionsQueue-ARN --attributes RawMessageDelivery=true
```
\
Navigate to the main queue in the AWS console and paste the QueuePolicy.json contents as the access policy.
- *Replace the placeholder ARN after the "Resource" value with the Queue ARN.*
- *Replace the placeholder ARN after the "aws:SourceArn" value with the Topic ARN.*
\
<br><br/>
### 7. Create Event Trigger <br><br/>

Create the event source mapping for the SubmissionParse function.
- *This will link the Queue to the SubmissionParse function.*
- *Replace the placeholder ARN after the --event-source-arn parameter with the Queue ARN.*
```
aws lambda create-event-source-mapping --function-name SubmissionParse --event-source-arn ZenputSubmissionsQueue-ARN
```
\
Create the scheduled event.
- *Change the rate to desired value, in testing 5 minutes seemed to work best.*
```
aws events put-rule --name GetFormSubmissionEvent --schedule-expression "rate(5 minutes)" 
```
\
Using the ARN from the output, create the proper lambda permissions.
- *This will allow the event trigger to invoke the GetFormSubmission function.*
- *Replace the placeholder ARN after the --source-arn with the Event ARN.*
```
aws lambda add-permission --function-name GetFormSubmission --statement-id GetFormSubmissionEvent --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn GetFormSubmissionEvent-ARN
```
\
Create the target for the event.
- *This will link the Event to the GetFormSubmission function.*
- *Replace the placeholder ARN after the 'Arn'=' parameter with the GetFormSubmission ARN.*
```
aws events put-targets --rule GetFormSubmissionEvent --targets 'Id'='1','Arn'='GetFormSubmission-ARN'
```
Or for Windows:
```
aws events put-targets --rule GetFormSubmissionEvent --targets 'Id=1','Arn=GetFormSubmission-ARN'
```
