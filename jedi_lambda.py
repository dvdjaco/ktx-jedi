import json
import boto3
import base64
import os

kms_key_id = os.environ.get('jedi_key')
drop_bucket = os.environ.get('jedi_drop')
secret_bucket = os.environ.get('jedi_secret')
s3_client = boto3.client('s3')
kms_client = boto3.client('kms')

def save_secret(secret, key):
    # Encrypts and saves the string "secret" as an object with the name "key" to the jedi_secret bucket
    # Encrypt the secret
    e_secret = kms_client.encrypt(
        KeyId=kms_key_id,
        Plaintext=str(secret)
        )
    ciphertext = e_secret['CiphertextBlob']

    # Save the secret to the secret S3 bucket
    s3_client.put_object(
        Bucket=secret_bucket,
        Key=key,
        Body=ciphertext
        )

def load_secret(key):
    # Decrypts the object "key" and returns it
    # Read the secret from the secret S3 bucket
    secret_object = s3_client.get_object(
        Bucket=secret_bucket,
        Key=key,
        )
    e_secret  = secret_object['Body'].read()

    # Decrypt the secret
    secret = kms_client.decrypt(
        KeyId=kms_key_id,
        CiphertextBlob=e_secret,
        )
    return(secret['Plaintext'])
    
def file_exists_in_bucket(key, bucket):
    # Check if a key exists in the bucket
    try:
        s3_client.head_object(Bucket=bucket, Key=key)
        return True
    except s3_client.exceptions.ClientError as e:
        if e.response['Error']['Code'] == '404':
            return False

def cleanup_bucket(bucket):
    # Delete all objects from the bucket
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix='')
    for object in response['Contents']:
        s3_client.delete_object(Bucket=bucket, Key=object['Key'])
    print('Drop bucket cleaned.')

def lambda_handler(event, context):
    # Retrieve S3 PUT event
    put_event = event['Records'][0]['s3']
    drop_bucket = put_event['bucket']['name']
    drop_key = put_event['object']['key']

    drop_object = s3_client.get_object(Bucket=drop_bucket, Key=drop_key)
    
    # The dropped file is a manifest
    if drop_key == 'manifest':
        new_manifest = json.loads(drop_object['Body'].read().decode('utf-8'))

        # If we don't have a stored mission we save the manifest and exit
        if not file_exists_in_bucket('mission', secret_bucket):
            print("Received a manifest but we don't have a mission.")
            save_secret(json.dumps(new_manifest), 'manifest')
            cleanup_bucket(drop_bucket)
            return
        
        # Check if we have a stored manifest and store the merged manifest if we do
        if file_exists_in_bucket('manifest', secret_bucket):
            old_manifest = json.loads(load_secret('manifest').decode('utf-8'))
            manifest = {**old_manifest, **new_manifest}
        else:
            manifest = new_manifest
        save_secret(json.dumps(manifest), 'manifest')

        # Return if we don't have a match
        mission = load_secret('mission').decode('utf-8')
        if not mission in manifest:
            print('Current objective not found in manifest.')
            cleanup_bucket(drop_bucket)
            return
        else:
            # There's a match, print it and exit
            location = manifest[mission]['planet']
            print('Our current objective is located in: ', location)
            cleanup_bucket(drop_bucket)
            return {
                'statusCode': 200,
                'body': {
                    'Planet': location,
                    }
                }
                
    # The dropped file is a mission, read and save it.
    elif drop_key == 'mission':
        mission = drop_object['Body'].read().decode('utf-8').strip()
        save_secret(mission, 'mission')
        
        # Return if we don't have a manifest
        if not file_exists_in_bucket('manifest', secret_bucket):
            print("Received a mission but we don't have a manifest.")
            cleanup_bucket(drop_bucket)
            return
        else:
            manifest = json.loads(load_secret('manifest').decode('utf-8'))
        
        # Return if we don't have a match
        if not mission in manifest:
            print('Current objective not found in manifest.')
            cleanup_bucket(drop_bucket)
            return
        else:
            location = manifest[mission]['planet']
            print('Our current objective is located in: ', location)
            cleanup_bucket(drop_bucket)
            return {
                'statusCode': 200,
                'body': {
                    'Planet': location,
                    }
                }
    
    else:
        # The dropped file is neither mission nor manifest, cleanup and exit
        print('File not recognized.')
        cleanup_bucket(drop_bucket)
        return


