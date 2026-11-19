import 'package:supabase_flutter/supabase_flutter.dart';

const kSupabaseUrl = 'https://mgssvmfhcepybwcvafxz.supabase.co';
const kSupabaseAnonKey = 'sb_publishable_yFxYm5-zCet2HIfq_rU_yA_IkCMdZM9';

bool supabaseReady = false;

SupabaseClient get supabase => Supabase.instance.client;
bool get isSignedIn => supabaseReady && supabase.auth.currentUser != null;

Future<T> netCall<T>(Future<T> f) => f.timeout(Duration(seconds: 10));
