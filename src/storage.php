<?php
// Capsule attachments live in S3 under uploads/. Database rows still store only
// the random filename, including for files migrated from the local disk.

function storage_client(): Aws\S3\S3Client
{
    static $client = null;
    if ($client === null) {
        // The default credential chain obtains temporary credentials from the
        // EC2 instance role. No access keys belong in application configuration.
        $client = new Aws\S3\S3Client([
            'version' => '2006-03-01',
            'region' => config('AWS_REGION', 'eu-central-1'),
        ]);
    }
    return $client;
}

function storage_bucket(): string
{
    $bucket = config('S3_BUCKET');
    if ($bucket === null) {
        throw new RuntimeException('S3_BUCKET is not configured.');
    }
    return $bucket;
}

// Save an uploaded file and return its random filename, without the S3 prefix.
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;
    $mime = mime_content_type($uploadedFile['tmp_name']);
    if ($mime === false) {
        throw new RuntimeException('Could not determine the uploaded file type.');
    }

    storage_client()->putObject([
        'Bucket' => storage_bucket(),
        'Key' => 'uploads/' . $storedName,
        'SourceFile' => $uploadedFile['tmp_name'],
        'ContentType' => $mime,
    ]);
    return $storedName;
}

function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    // Without VersionId, deletion preserves history in the versioned bucket.
    storage_client()->deleteObject([
        'Bucket' => storage_bucket(),
        'Key' => 'uploads/' . basename($storedName),
    ]);
}

// The controller checks capsule access and opening time before calling this.
// The browser follows a short-lived URL and receives the file directly from S3.
function storage_stream(string $storedName, string $mime, string $downloadName, string $disposition): void
{
    $asciiName = preg_replace('/[^A-Za-z0-9._ -]/', '_', $downloadName);
    $contentDisposition = sprintf(
        '%s; filename="%s"; filename*=UTF-8\'\'%s',
        $disposition === 'attachment' ? 'attachment' : 'inline',
        $asciiName,
        rawurlencode($downloadName)
    );

    $client = storage_client();
    $command = $client->getCommand('GetObject', [
        'Bucket' => storage_bucket(),
        'Key' => 'uploads/' . basename($storedName),
        'ResponseContentType' => $mime,
        'ResponseContentDisposition' => $contentDisposition,
    ]);
    $request = $client->createPresignedRequest($command, '+5 minutes');

    header('Cache-Control: private, no-store');
    redirect((string) $request->getUri());
}
