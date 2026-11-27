class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  // Public SDK keys from RevenueCat (app-specific, safe to ship in the app).
  static const revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const revenueCatAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  // Cloudflare Turnstile (bot protection for sign up and login). Empty site key = no captcha (local development).
  static const turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  // Hostname allowed for the widget on mobile (the widget runs in a web view), e.g. https://app.example.com/
  static const turnstileBaseUrl = String.fromEnvironment('TURNSTILE_BASE_URL', defaultValue: 'http://localhost/');
  // Required by the stores: public links to the privacy policy and the terms of use.
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');
  static const termsUrl = String.fromEnvironment('TERMS_URL');
  static bool get captchaEnabled => turnstileSiteKey.isNotEmpty;
}
