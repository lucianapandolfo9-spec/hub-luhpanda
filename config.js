// Hub Luh Panda — configuração compartilhada
// Mesmo projeto Supabase do Certo Agro e do aprovi.ai (schema `hub`, isolado dos dois).
const HUB_SUPABASE_URL = "https://tscnqvuzlfagotirgjbz.supabase.co";
const HUB_SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRzY25xdnV6bGZhZ290aXJnamJ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4Mzc2NjgsImV4cCI6MjA5ODQxMzY2OH0.9PmwjxNPVIVOy3eenYAqlLSKmhyYeQUSQXz_PvixSB0";
const HUB_ADMIN_EMAIL = "lucianapandolfo9@gmail.com";

const hubClient = supabase.createClient(HUB_SUPABASE_URL, HUB_SUPABASE_ANON_KEY);
