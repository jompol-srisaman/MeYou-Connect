# MeYou Connect

Engineering repository สำหรับระบบ MeYou Connect / Work Connect

## Status
TEST-FIRST IMPLEMENTATION

## Architecture
ระบบจะพัฒนาตาม Architecture ที่กำหนดไว้ โดยเริ่มจาก:
1. Event / Automation Kernel
2. Supabase / PostgreSQL
3. Security / Reliability
4. Analytics / Dashboard
5. Candidate / Partner / Client Portal

## Important
- Production Source of Truth ปัจจุบันยังเป็น Google Sheets + Google Drive
- Development ต้องทำใน TEST ก่อน
- ห้าม commit API Key, Database Password หรือ Secret ลง repository
