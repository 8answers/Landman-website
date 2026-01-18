# Deployment Guide for Netlify

## Prerequisites
1. Flutter SDK installed and configured
2. GitHub account with this repository
3. Netlify account (https://netlify.com)

## Setup Instructions

### 1. Connect Repository to Netlify
- Go to https://app.netlify.com
- Click "Add new site" → "Import an existing project"
- Select GitHub and authorize
- Choose the `8answers/Landman-website` repository
- Click "Deploy site"

### 2. Configure Build Settings
The build settings are already configured in `netlify.toml`:
- **Build command**: `flutter build web --release`
- **Publish directory**: `build/web`

### 3. Set Environment Variables (if needed)
If your Flutter app requires environment variables:
1. Go to Site settings → Build & deploy → Environment
2. Add any required variables

### 4. Configure GitHub Actions
The GitHub Actions workflow is configured in `.github/workflows/deploy.yml` to automatically deploy on every push to main.

To enable automatic deploys:
1. Go to your Netlify Site settings
2. Copy your Site ID from "General" tab
3. Go to your GitHub repository settings
4. Add these secrets:
   - `NETLIFY_AUTH_TOKEN`: Your Netlify personal access token (from https://app.netlify.com/user/applications#personal-access-tokens)
   - `NETLIFY_SITE_ID`: Your Netlify Site ID

### 5. Deploy
- Push changes to the `main` branch
- GitHub Actions will automatically build and deploy to Netlify
- Check the deployment status in the "Actions" tab on GitHub

## Troubleshooting

If the build fails:
1. Check GitHub Actions logs in the "Actions" tab
2. Ensure Flutter is properly configured
3. Verify `pubspec.yaml` has all dependencies

For Netlify deployment issues:
1. Check Netlify deploy logs in the "Deploys" tab
2. Verify the publish directory is correct
3. Check environment variables are set properly
