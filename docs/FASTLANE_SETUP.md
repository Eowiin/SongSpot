# Fastlane Setup for TestFlight Deployment

This guide will help you set up Fastlane to deploy your iOS app to TestFlight.

## Prerequisites

- Xcode installed
- Ruby installed (macOS comes with Ruby)
- An Apple Developer account with Admin access

## Step 0: Apple Developer & App Store Connect Setup

Before using Fastlane, you need to set up your app in Apple's systems.

### 0.1 Register App Identifier in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles** → **Identifiers**
3. Click the **+** button to create a new identifier
4. Select **App IDs** and click **Continue**
5. Select **App** and click **Continue**
6. Configure the identifier:
   - **Description**: SongSpot (or your preferred name)
   - **Bundle ID**: Select "Explicit" and enter `com.songspot.app`
   - **Capabilities**: Enable any capabilities your app needs (e.g., Push Notifications, In-App Purchase, etc.)
7. Click **Continue** and then **Register**

### 0.2 Create App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** button → **New App**
3. Fill in the required information:
   - **Platform**: iOS
   - **Name**: SongSpot (your app's display name)
   - **Primary Language**: Select your primary language
   - **Bundle ID**: Select `com.songspot.app` from the dropdown (it should appear after completing step 0.1)
   - **SKU**: A unique identifier (e.g., `songspot-001` or `com.songspot.app`)
   - **User Access**: Full Access (recommended)
4. Click **Create**

**Important**: The app must exist in App Store Connect before Fastlane can upload builds. Fastlane will not create the initial app listing for you.

### 0.3 Configure Code Signing in Xcode

1. Open the project in Xcode: `songspot_mobile/ios/Runner.xcworkspace`
2. Select the **Runner** target in the project navigator
3. Go to the **Signing & Capabilities** tab
4. Ensure the following:
   - **Team**: Select your development team (should be `WM42CA5NH5`)
   - **Automatically manage signing**: Checked (recommended for most cases)
   - **Bundle Identifier**: Should show `com.songspot.app`
5. Xcode will automatically create/download the necessary certificates and provisioning profiles

### 0.4 Verify Your App Builds in Xcode

Before setting up Fastlane, make sure your app builds successfully:

1. In Xcode, select a device (not simulator) or "Any iOS Device"
2. Product → Archive
3. If the archive succeeds, you're ready to proceed with Fastlane setup

## Step 1: Install Dependencies

Navigate to the iOS directory and install the required gems:

```bash
cd songspot_mobile/ios
bundle config set --local path 'vendor/bundle'
bundle install
```

**Note:** The first command configures bundler to install gems locally in the `vendor/bundle` directory. This avoids permission issues with system-wide gem installation and keeps dependencies isolated to your project.

If you don't have Bundler installed:

```bash
gem install bundler
bundle config set --local path 'vendor/bundle'
bundle install
```

**Important:** Always use `bundle exec` before fastlane commands to ensure you're using the correct gem versions.

## Step 2: Create App Store Connect API Key

The Fastfile uses App Store Connect API authentication which is more secure and doesn't require 2FA prompts.

### Creating the API Key:

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **Users and Access** → **Integrations** → **App Store Connect API**
3. Click the **+** button to create a new key
4. Give it a name (e.g., "Fastlane CI")
5. Select **Admin** access (or **Developer** if you only need build upload)
6. Click **Generate**
7. Download the `.p8` file (you can only download it once!)
8. Note down the **Key ID** and **Issuer ID**

### Setting up Environment Variables:

You need to set three environment variables:

1. **ASC_KEY_ID**: The Key ID from App Store Connect
2. **ASC_ISSUER_ID**: The Issuer ID from App Store Connect
3. **ASC_P8_FILE**: Base64-encoded content of the .p8 file

#### Option A: Using a .env file (for local development)

Create a `.env` file in `songspot_mobile/ios/`:

```bash
# Convert .p8 file to base64
base64 -i /path/to/your/AuthKey_XXXXXXXXXX.p8 | pbcopy

# Create .env file
cat > .env <<EOF
ASC_KEY_ID=YOUR_KEY_ID
ASC_ISSUER_ID=YOUR_ISSUER_ID
ASC_P8_FILE=<paste the base64 output here>
EOF
```

**Important:** Add `.env` to your `.gitignore` to keep credentials secure!

#### Option B: Export environment variables (temporary)

```bash
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_P8_FILE=$(base64 -i /path/to/your/AuthKey_XXXXXXXXXX.p8)
```

#### Option C: For CI/CD (GitHub Actions, etc.)

Add the three values as secrets in your CI/CD platform and reference them in your workflow.

## Step 3: Verify Setup

Test that Fastlane can authenticate:

```bash
cd songspot_mobile/ios
bundle exec fastlane run validate_app_store_connect_api_key
```

## Step 4: Deploy to TestFlight

Once everything is set up, deploy to TestFlight:

```bash
cd songspot_mobile/ios
bundle exec fastlane beta
```

This will:
1. Authenticate with App Store Connect
2. Fetch the latest TestFlight build number
3. Increment the build number
4. Build the IPA file
5. Upload to TestFlight

## Available Lanes

### `beta`
Builds and uploads to TestFlight for internal/external testing.

```bash
bundle exec fastlane beta
```

### `release`
Builds, uploads, and submits to the App Store for review.

```bash
bundle exec fastlane release
```

## Troubleshooting

### Permission errors during bundle install
If you get permission errors trying to write to `/opt/homebrew/lib/ruby/gems/` or similar system directories:

```bash
bundle config set --local path 'vendor/bundle'
bundle install
```

This configures bundler to install gems locally instead of system-wide.

### "No signing certificate found"
Make sure you have a valid distribution certificate and provisioning profile set up in your Apple Developer account and Xcode.

### "Could not find build number"
This might be the first build. The script handles this by starting at build number 1.

### "API key authentication failed"
- Verify all three environment variables are set correctly
- Ensure the base64 encoding of the .p8 file is correct
- Check that the API key hasn't been revoked in App Store Connect

### Build fails
- Ensure your app builds successfully in Xcode first
- Check that the scheme "Runner" exists and is shared
- Verify code signing settings in Xcode

### Command not found: fastlane
Always use `bundle exec fastlane` instead of just `fastlane` to ensure you're using the project's bundled version.

## Security Best Practices

1. Never commit the `.p8` file or `.env` file to version control
2. Add these to `.gitignore` (already configured):
   ```
   .env
   *.p8
   fastlane/report.xml
   fastlane/Preview.html
   fastlane/screenshots
   fastlane/test_output
   vendor/bundle
   .bundle
   ```
3. Use different API keys for different environments (development, CI/CD)
4. Regularly rotate API keys
5. Use the minimum required permissions for API keys

## Additional Resources

- [Fastlane Documentation](https://docs.fastlane.tools/)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
