# CloudFormation Deployment
One-Click Deployment for the PullZenputForms Architecture
<br><br/>
In order to use the template, follow the instructions below:
1. Create an S3 bucket. Make sure to uncheck the "Block all public access" option.
2. Upload the SubmissionParse.zip and layer.zip files to the bucket.
3. Deploy the PullZenputForms.yaml template in CloudFormation.
4. After the stack creation is complete, the S3 bucket can be deleted.
5. By default, the architecture will send all processed forms to the Alert Recipient address that is specified. Once you have confirmed that the deployment is working as intended, this can be changed by editing Line 54 of the SubmissionParse Lambda. Remove the "ALERT_RECIPIENT" text that follows the = sign, and uncomment the rest of the line in order to start sending the forms to the proper users.
