// Public values (the anon key is designed to ship inside the app). Can be overridden with --dart-define.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://pugwabgtqvdzajwbrkig.supabase.co');
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1Z3dhYmd0cXZkemFqd2Jya2lnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NDcyNjMsImV4cCI6MjEwODUyMzI2M30.5kq4fmRpNrLKdJZJtOw5WKYIRQ2Dr1YgA6Z8n_5qfbY',
);
