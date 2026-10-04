$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$serviceAccountPath = Join-Path $projectRoot "hmu-flutter-version-firebase-adminsdk-fbsvc-02e3308b66.json"

if (!(Test-Path -LiteralPath $serviceAccountPath)) {
  throw "Missing Firebase service account file at $serviceAccountPath"
}

$serviceAccount = Get-Content -Raw -LiteralPath $serviceAccountPath | ConvertFrom-Json

$supabaseUrl = "https://xmhbrnkukhmzizkiyyhg.supabase.co"
$projectId = $serviceAccount.project_id
$clientEmail = $serviceAccount.client_email
$privateKey = $serviceAccount.private_key

Write-Host ""
Write-Host "Run these commands after you have the Supabase CLI installed and linked:" -ForegroundColor Cyan
Write-Host ""
Write-Host "supabase login"
Write-Host "supabase link --project-ref xmhbrnkukhmzizkiyyhg"
Write-Host "supabase secrets set SUPABASE_URL=$supabaseUrl"
Write-Host "supabase secrets set FIREBASE_PROJECT_ID=$projectId"
Write-Host "supabase secrets set FIREBASE_CLIENT_EMAIL=$clientEmail"
Write-Host "supabase secrets set FIREBASE_PRIVATE_KEY=""$privateKey"""
Write-Host "supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<YOUR_SERVICE_ROLE_KEY>"
Write-Host "supabase functions deploy send-order-status --no-verify-jwt"
Write-Host ""
Write-Host "Then create a Database Webhook on table 'orders' for UPDATE events and point it to:"
Write-Host "https://xmhbrnkukhmzizkiyyhg.functions.supabase.co/send-order-status"
Write-Host ""
Write-Host "Webhook payload fields used by the function:"
Write-Host "- record.id"
Write-Host "- record.customer_id"
Write-Host "- record.order_status"
Write-Host "- old_record.order_status"
