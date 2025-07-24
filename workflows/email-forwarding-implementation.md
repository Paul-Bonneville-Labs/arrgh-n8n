# Complete Email Forwarding Implementation for Arrgh Email Processor

## Overview
This document provides step-by-step instructions to add **complete email forwarding** functionality to the "Arrgh Email Processor" n8n workflow. This implementation forwards the **entire .eml file** as an attachment, preserving all formatting, headers, attachments, and MIME structure exactly as the recipient would see it.

## Current Workflow
- **Name**: Arrgh Email Processor
- **ID**: cplr7F8xgOQ0lwpa
- **Backup Created**: 2025-07-11 (see `backups/2025-07-11/arrgh-email-processor-backup.json`)

## Enhanced Requirements
- Forward **complete .eml files** to paul@paulbonneville.com as attachments
- Preserve **100% email fidelity**: all headers, attachments, MIME structure, formatting
- Email clients render the .eml attachment as a normal viewable email
- Add "[n8n processed]" prefix to forwarding email subject
- Maintain parallel processing with existing entity extraction
- Support emails with attachments, complex HTML, and multipart content

## Implementation Steps

### Step 1: Open Workflow
1. Navigate to n8n.paulbonneville.com
2. Open the "Arrgh Email Processor" workflow
3. Ensure you're in edit mode

### Step 2: Modify "Extract Data from Email" Node

**Update Python Code to Expose Raw Content:**

The current Python node needs to be modified to expose the raw .eml content for forwarding. Replace the return statement at the end of the Python code with:

```python
# Return the entire message object as structured Python objects
# IMPORTANT: Include raw_content for complete email forwarding
return [{
    "json": {
        **sns_message,
        "raw_content": raw_email_content  # Add this for .eml forwarding
    }
}]
```

**Add this variable at the top of the Python code (after parsing SNS message):**

```python
# Store the raw email content for complete forwarding
raw_email_content = sns_message.get('content', '')
```

**Complete Modified Python Code:**

Replace the entire Python code in the "Extract Data from Email" node with:

```python
import json
import re

def parse_json_strings(obj):
    """Recursively parse JSON strings in nested objects"""
    if isinstance(obj, dict):
        result = {}
        for key, value in obj.items():
            result[key] = parse_json_strings(value)
        return result
    elif isinstance(obj, list):
        return [parse_json_strings(item) for item in obj]
    elif isinstance(obj, str):
        # Try to parse as JSON if it looks like JSON
        stripped = obj.strip()
        if (stripped.startswith('{') and stripped.endswith('}')) or \
           (stripped.startswith('[') and stripped.endswith(']')):
            try:
                parsed = json.loads(obj)
                return parse_json_strings(parsed)  # Recursively parse nested JSON
            except (json.JSONDecodeError, ValueError):
                pass
        return obj
    else:
        return obj

def parse_email_content(raw_content):
    """Custom email parser that works in n8n environment"""
    if not isinstance(raw_content, str):
        return raw_content
    
    try:
        # Split headers and body (empty line separates them)
        parts = raw_content.split('\n\n', 1)
        if len(parts) != 2:
            # Try with \r\n\r\n
            parts = raw_content.split('\r\n\r\n', 1)
        
        if len(parts) == 2:
            headers_text, body = parts
        else:
            # If no clear separation, treat everything as headers
            headers_text = raw_content
            body = ""
        
        # Parse headers
        headers = {}
        current_header = None
        current_value = ""
        
        for line in headers_text.split('\n'):
            line = line.rstrip('\r')
            
            # Check if this is a continuation line (starts with space or tab)
            if line.startswith((' ', '\t')) and current_header:
                current_value += ' ' + line.strip()
            else:
                # Save previous header if exists
                if current_header:
                    headers[current_header] = current_value.strip()
                
                # Parse new header
                if ':' in line:
                    header_name, header_value = line.split(':', 1)
                    current_header = header_name.strip()
                    current_value = header_value.strip()
                else:
                    current_header = None
        
        # Don't forget the last header
        if current_header:
            headers[current_header] = current_value.strip()
        
        # Clean up the body (remove quoted-printable encoding artifacts)
        clean_body = body.replace('=\n', '').replace('=\r\n', '')
        
        # Decode some common quoted-printable sequences
        clean_body = clean_body.replace('=3D', '=')
        clean_body = clean_body.replace('=20', ' ')
        
        # Determine content type
        content_type = headers.get('Content-Type', '').split(';')[0].strip()
        if not content_type:
            content_type = 'text/plain'
        
        return {
            "headers": headers,
            "body": clean_body,
            "content_type": content_type,
            "is_multipart": 'multipart' in content_type.lower()
        }
        
    except Exception as e:
        print(f"Email parsing failed: {e}")
        return raw_content

# Get the input data from webhook - n8n Python node uses 'items' variable
json_data = items[0].json
print('Input data:', json_data)

# Parse the SNS message from the webhook
sns_message = None
if 'body' in json_data:
    # If body is a string, parse it
    if isinstance(json_data['body'], str):
        sns_body = json.loads(json_data['body'])
        sns_message = json.loads(sns_body['Message'])
    else:
        # If body is already an object
        sns_message = json.loads(json_data['body']['Message'])
elif 'Message' in json_data:
    # Direct Message field
    sns_message = json.loads(json_data['Message'])
else:
    raise Exception('Could not find SNS Message in input data')

# Store the raw email content for complete forwarding (.eml file)
raw_email_content = sns_message.get('content', '')

# Recursively parse any JSON strings within the message
sns_message = parse_json_strings(sns_message)

# Parse the email content if it exists
if 'content' in sns_message:
    sns_message['content'] = parse_email_content(sns_message['content'])

# Add S3 information to the message object
sns_message['s3Bucket'] = 'n8n-inbound-emails-production'
sns_message['s3ObjectKey'] = 'emails/' + sns_message['mail']['messageId']

print(f"Extracted complete message object with S3 info:")
print(f"  Message ID: {sns_message['mail']['messageId']}")
print(f"  S3 Location: s3://{sns_message['s3Bucket']}/{sns_message['s3ObjectKey']}")

# Return the entire message object as structured Python objects
# IMPORTANT: Include raw_content for complete email forwarding
return [{
    "json": {
        **sns_message,
        "raw_content": raw_email_content  # Raw .eml content for forwarding
    }
}]
```

### Step 3: Add Complete Email Forwarding Node

**Add New Node:**
1. Click the "+" button after "Extract Data from Email" node
2. Search for and select "Email Send" 
3. Name the node: "Forward Complete Email"
4. Position it below the "Extract Data from Email" node

**Configure Node Parameters for .eml Attachment:**

| Field | Value |
|-------|-------|
| **From Email** | `arrgh@paulbonneville.com` |
| **To Email** | `paul@paulbonneville.com` |
| **Subject** | `[n8n processed] Original Email: {{ $json.content.headers.Subject }}` |
| **Text** | `Please see attached original email.` |
| **Attachments** | **Configure Attachment (CRITICAL):** |
| - **Property Name** | `emailAttachment` |
| - **File Name** | `{{ $json.mail.messageId }}.eml` |
| - **File Content** | `{{ $json.raw_content }}` |
| - **MIME Type** | `message/rfc822` |
| **SMTP Credentials** | AWS SES SMTP account (existing) |

**Important Attachment Configuration Notes:**
- **File Name**: Uses the email message ID to create unique .eml files
- **File Content**: Uses `raw_content` which contains the complete .eml file
- **MIME Type**: `message/rfc822` ensures email clients recognize it as an email file
- **Property Name**: Can be any name, used internally by n8n

**Alternative Method - Using Binary Data:**

If the attachment configuration above doesn't work, use this alternative approach:

1. **First, add a "Set" node** before the email send:
   - **Name**: "Prepare Email Attachment"
   - **Operation**: "Set"
   - **Value**: `{{ $json.raw_content }}`
   - **Type**: "Binary"
   - **Property Name**: `emailFile`
   - **File Name**: `{{ $json.mail.messageId }}.eml`
   - **MIME Type**: `message/rfc822`

2. **Then configure Email Send node**:
   - **Attachments**: Select binary property `emailFile`

### Step 4: Connect Nodes

**Add Connection:**
- From: "Extract Data from Email" (main output)
- To: "Forward Complete Email" (main input)

**Verify Existing Connection Remains:**
- "Extract Data from Email" → "Call Newsletter API" should still exist

### Step 5: Updated Workflow Flow

```
Webhook (SNS) → Is Subscription Confirmation?
                ├── (True) → Confirm Subscription → Subscription Response
                └── (False) → Is Email Notification? 
                            └── (True) → Extract Data from Email (MODIFIED)
                                        ├── Call Newsletter API → Send Summary → Success Response
                                        └── Forward Complete Email (NEW - .eml attachment)
```

## Complete Email Forwarding Details

### Subject Format
- **Template**: `[n8n processed] Original Email: {{ $json.content.headers.Subject }}`
- **Example**: "Newsletter Update" becomes "[n8n processed] Original Email: Newsletter Update"

### Email Content
- **Forwarding Email Body**: Simple text: "Please see attached original email."
- **Attachment**: Complete .eml file with original headers, formatting, attachments
- **File Name**: `{{ $json.mail.messageId }}.eml` (unique per email)
- **MIME Type**: `message/rfc822` (standard email file format)

### .eml File Contents
- **Complete Headers**: All original email headers (From, To, Date, Message-ID, etc.)
- **Full MIME Structure**: Multipart boundaries, Content-Type headers
- **Attachments Preserved**: All original attachments included
- **Formatting Intact**: HTML, CSS, images, links exactly as sent
- **Email Signatures**: DKIM, SPF, authentication headers preserved

### Key Features
- **100% Fidelity**: Email renders exactly as original in any email client
- **Universal Compatibility**: .eml files open in Outlook, Gmail, Apple Mail, etc.
- **Attachment Support**: Forwards emails with attachments completely intact
- **Parallel Processing**: Forwarding runs simultaneously with entity extraction
- **Error Isolation**: If forwarding fails, entity extraction continues
- **Professional Format**: Standard email forwarding approach used by email servers
- **Searchable**: Email clients can index and search the .eml content
- **Consistent SMTP**: Uses same AWS SES credentials as summary emails

## Testing Procedure

### Test Complete Email Forwarding

**Phase 1: Basic Text Email Test**
1. Send a simple text email to: `test@arrgh.paulbonneville.com`
   - **Subject**: "Test Text Email"  
   - **Body**: Plain text content
2. Verify two emails received at `paul@paulbonneville.com`:
   - **Forwarded Email**: Subject "[n8n processed] Original Email: Test Text Email"
   - **Summary Email**: "Arrgh! Email newsletter was parsed"
3. **Critical Test**: Open the .eml attachment in forwarded email
   - Verify it opens as a normal email in your email client
   - Check all headers, formatting, and content match the original

**Phase 2: HTML Email with Attachments Test**
1. Send an HTML email with attachment to: `test@arrgh.paulbonneville.com`
   - **Subject**: "HTML Email with Attachment"
   - **Body**: Rich HTML content (images, links, formatting)
   - **Attachment**: Include a PDF or image file
2. Verify forwarded email contains .eml attachment
3. **Critical Test**: Open the .eml attachment
   - Verify HTML formatting renders correctly
   - Verify original attachment is accessible and opens properly
   - Check all images and links work as in original

**Phase 3: Complex Email Test**
1. Send a complex multipart email:
   - **Subject**: "Complex Newsletter Test"
   - **Body**: HTML with embedded images, tables, CSS
   - **Multiple attachments**: PDF, image, document
2. **Critical Test**: Open .eml attachment and verify:
   - All attachments present and functional
   - HTML/CSS formatting intact
   - Email appears identical to original

### Enhanced Validation Checklist
- [ ] **Python Code Updated**: "Extract Data from Email" node exposes `raw_content`
- [ ] **Email forwarding node added**: "Forward Complete Email" configured
- [ ] **Connection established**: From "Extract Data from Email" to forwarding node  
- [ ] **Subject format correct**: "[n8n processed] Original Email: [subject]"
- [ ] **Attachment configuration**: .eml file with `message/rfc822` MIME type
- [ ] **File naming**: Uses `{{ $json.mail.messageId }}.eml` format
- [ ] **.eml files open properly**: Email clients render as normal emails
- [ ] **Attachments preserved**: All original attachments accessible in .eml
- [ ] **HTML formatting intact**: Rich content renders exactly as original
- [ ] **Headers preserved**: All email metadata and routing information included
- [ ] **Entity extraction still works**: Parallel processing functions normally
- [ ] **Summary notification sent**: Analytics email received as before
- [ ] **Webhook responds successfully**: No errors in n8n execution logs

### File Size and Performance Considerations
- [ ] **Large email test**: Send email >5MB (with attachments) to test limits
- [ ] **Performance check**: Verify forwarding doesn't slow entity extraction
- [ ] **Error handling**: Test with malformed emails to ensure graceful failure

## Troubleshooting

### Common Issues

**1. .eml Attachment Not Working**
- **Issue**: Email forwards but no .eml attachment
- **Solution**: Verify `raw_content` field is available in Python node output
- **Check**: Ensure Python code includes `"raw_content": raw_email_content` in return statement
- **Alternative**: Use binary data method with "Set" node before email send

**2. .eml File Won't Open in Email Client**
- **Issue**: Attachment exists but doesn't open as email
- **Solution**: Verify MIME type is set to `message/rfc822`
- **Check**: File extension is `.eml` not `.txt` or other format
- **Test**: Try opening .eml file with different email clients

**3. Missing Raw Content**
- **Issue**: `{{ $json.raw_content }}` shows empty or undefined
- **Solution**: Update Python code to store raw content before parsing
- **Check**: Verify `raw_email_content = sns_message.get('content', '')` line exists
- **Debug**: Add `print(f"Raw content length: {len(raw_email_content)}")` to Python code

**4. Attachment Too Large**
- **Issue**: Large emails fail to forward
- **Solution**: AWS SES has 10MB attachment limit
- **Alternative**: Use S3 method instead of direct attachment
- **Check**: Monitor email sizes in workflow execution logs

**5. SMTP Credentials**
- Ensure "AWS SES SMTP account" is selected
- Verify credentials are valid and active
- Check AWS SES sending limits and quotas

**6. Template Variables**
- Subject: `[n8n processed] Original Email: {{ $json.content.headers.Subject }}`
- Attachment: `{{ $json.raw_content }}` (not `$json.content.body`)
- File name: `{{ $json.mail.messageId }}.eml`
- Check for typos in variable names

**7. Node Connections**
- Verify connection from "Extract Data from Email" to "Forward Complete Email"
- Ensure existing workflow connections remain intact
- Check that both forwarding and entity extraction paths work

**8. Email Client Compatibility**
- **Gmail**: May show .eml as downloadable attachment, not inline preview
- **Outlook**: Usually opens .eml files directly as emails
- **Apple Mail**: Opens .eml files as viewable emails
- **Solution**: Download and open .eml file if not previewing inline

## Rollback Procedure

If issues occur:
1. **Deactivate** the modified workflow
2. **Import backup** from `backups/2025-07-11/arrgh-email-processor-backup.json`
3. **Verify webhook URL** matches original configuration
4. **Reactivate** the restored workflow

## Monitoring

**Check Execution Logs:**
- Monitor n8n workflow executions
- Watch for email send failures
- Verify both forwarding and entity extraction complete

**Email Verification:**
- Confirm paul@paulbonneville.com receives forwarded emails
- Check email formatting and subject prefixes
- Validate entity extraction summaries still arrive

## File Locations

- **Backup**: `workflows/backups/2025-07-11/arrgh-email-processor-backup.json`
- **Documentation**: `workflows/email-forwarding-implementation.md`
- **Related**: Integration documented in arrgh-fastapi project CLAUDE.md