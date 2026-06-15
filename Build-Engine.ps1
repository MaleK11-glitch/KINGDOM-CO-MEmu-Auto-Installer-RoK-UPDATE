param(
    [string]$Passphrase = "",
    [string]$OutputDir = "C:\Users\MaleK\AppData\Local\KINGDOM-CO_UPDATE"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "C# compiler not found!" }

$rng = [Security.Cryptography.RNGCryptoServiceProvider]::Create()

# Generate strong passphrase (96 bytes → 128 chars base64)
if ([string]::IsNullOrWhiteSpace($Passphrase)) {
    $bytes = [byte[]]::new(96)
    $rng.GetBytes($bytes)
    $Passphrase = [Convert]::ToBase64String($bytes)
}

# Create XOR mask for obfuscating passphrase in C# code
$mask = [byte[]]::new(37)
$rng.GetBytes($mask)
$passBytes = [Text.Encoding]::UTF8.GetBytes($Passphrase)
$xored = [byte[]]::new($passBytes.Length)
for ($i = 0; $i -lt $passBytes.Length; $i++) {
    $xored[$i] = $passBytes[$i] -bxor $mask[$i % $mask.Length]
}
$split = [math]::Floor($xored.Length / 2)
$p1 = $xored[0..($split - 1)]
$p2 = $xored[$split..($xored.Length - 1)]
$csP1 = [Convert]::ToBase64String($p1)
$csP2 = [Convert]::ToBase64String($p2)
$csMask = ($mask | ForEach-Object { "0x$('{0:x2}' -f $_)" }) -join ','

Write-Host "Passphrase: $($Passphrase.Substring(0,16))... ($($Passphrase.Length) chars)" -ForegroundColor Cyan

# ============================================================
# STEP 1: Collect ALL files
# ============================================================
Write-Host "[1/6] Collecting files..." -ForegroundColor Cyan

$files = @()

# PS1 scripts (merged launcher + all runtime scripts)
$ps1Files = @(
    "Launcher.ps1", "Start.ps1", "menu.ps1",
    "InstallROKAuto.ps1", "Build-Engine.ps1",
    "Publish-Update.ps1", "ManualUpdate.ps1",
    "version.txt"
)
foreach ($f in $ps1Files) {
    $fp = Join-Path $scriptDir $f
    if (Test-Path $fp) { $files += @{ Name = $f; Path = $fp } }
    else { Write-Host "  WARNING: $f not found" -ForegroundColor Yellow }
}

# Python scripts
$pythonFiles = @(
    "fetch_code_imap.py", "find_image.py", "check_alive.py"
)
foreach ($f in $pythonFiles) {
    $fp = Join-Path (Join-Path $scriptDir "Tools") $f
    if (-not (Test-Path $fp)) { $fp = Join-Path $scriptDir $f }
    if (Test-Path $fp) { $files += @{ Name = $f; Path = $fp } }
}

# Reference images
$refDir = Join-Path $scriptDir "ref_images"
if (Test-Path $refDir) {
    Get-ChildItem $refDir -File | % { $files += @{ Name = "ref_images/$($_.Name)"; Path = $_.FullName } }
}

Write-Host "  Collected $($files.Count) files" -ForegroundColor Green
$totalSize = ($files | % { (Get-Item $_.Path).Length } | Measure-Object -Sum).Sum
Write-Host "  Total size: $([math]::Round($totalSize / 1KB)) KB" -ForegroundColor Green

# ============================================================
# STEP 2: Build manifest + data blob
# ============================================================
Write-Host "[2/6] Building data blob..." -ForegroundColor Cyan

$blobStream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($blobStream)
$writer.Write([int32]$files.Count)
foreach ($f in $files) {
    $nameBytes = [Text.Encoding]::UTF8.GetBytes($f.Name)
    $dataBytes = [IO.File]::ReadAllBytes($f.Path)
    $writer.Write([int16]$nameBytes.Length)
    $writer.Write($nameBytes)
    $writer.Write([int32]$dataBytes.Length)
    $writer.Write($dataBytes)
}
$writer.Flush()
$plainBlob = $blobStream.ToArray()
$writer.Close(); $blobStream.Close()
Write-Host "  Blob: $($plainBlob.Length) bytes" -ForegroundColor Green

# ============================================================
# STEP 3: Derive 6 keys from passphrase (stronger KDF)
# ============================================================
Write-Host "[3/6] Deriving 6 keys (100000 iterations)..." -ForegroundColor Cyan

function Derive-Key($pass, $salt, $size=32) {
    $keyGen = New-Object Security.Cryptography.Rfc2898DeriveBytes($pass, [Text.Encoding]::UTF8.GetBytes($salt), 100000, [Security.Cryptography.HashAlgorithmName]::SHA512)
    return [byte[]]($keyGen.GetBytes($size))
}

$key1 = Derive-Key $Passphrase "KingdomCo-L1-AES2-2026" 32
$key2 = Derive-Key $Passphrase "KingdomCo-L2-XOR2-2026" 32
$key3 = Derive-Key $Passphrase "KingdomCo-L3-AES2-2026" 32
$key4 = Derive-Key $Passphrase "KingdomCo-L4-XOR2-2026" 32
$key5 = Derive-Key $Passphrase "KingdomCo-L5-AES2-2026" 32
$key6 = Derive-Key $Passphrase "KingdomCo-L6-XOR2-2026" 32

function XOR-Transform($data, $key) {
    $result = [byte[]]::new($data.Length)
    for ($i = 0; $i -lt $data.Length; $i++) {
        $result[$i] = $data[$i] -bxor $key[$i % $key.Length]
    }
    return $result
}

function AES-Encrypt($data, $key) {
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.GenerateIV()
    $encryptor = $aes.CreateEncryptor()
    $cipherBytes = $encryptor.TransformFinalBlock($data, 0, $data.Length)
    return $aes.IV + $cipherBytes
}

function AES-Decrypt($data, $key) {
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $iv = $data[0..15]
    $cipher = $data[16..($data.Length - 1)]
    $aes.IV = $iv
    $decryptor = $aes.CreateDecryptor()
    return $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length)
}

# ============================================================
# STEP 4: Apply 6-layer encryption
# ============================================================
Write-Host "[4/6] Applying 6-layer encryption..." -ForegroundColor Cyan

# Layer 1: AES-256 with key1
$layer1 = AES-Encrypt $plainBlob $key1
Write-Host "  L1 (AES-256): $($layer1.Length) bytes" -ForegroundColor DarkGray

# Layer 2: XOR with key2
$layer2 = XOR-Transform $layer1 $key2
Write-Host "  L2 (XOR):     $($layer2.Length) bytes" -ForegroundColor DarkGray

# Layer 3: AES-256 with key3
$layer3 = AES-Encrypt $layer2 $key3
Write-Host "  L3 (AES-256): $($layer3.Length) bytes" -ForegroundColor DarkGray

# Layer 4: XOR with key4
$layer4 = XOR-Transform $layer3 $key4
Write-Host "  L4 (XOR):     $($layer4.Length) bytes" -ForegroundColor DarkGray

# Layer 5: AES-256 with key5 (NEW)
$layer5 = AES-Encrypt $layer4 $key5
Write-Host "  L5 (AES-256): $($layer5.Length) bytes" -ForegroundColor DarkGray

# Layer 6: XOR with key6 (NEW)
$layer6 = XOR-Transform $layer5 $key6
Write-Host "  L6 (XOR):     $($layer6.Length) bytes" -ForegroundColor DarkGray

$encryptedBlob = $layer6

# ============================================================
# STEP 5: Generate C# source and compile DLL
# ============================================================
Write-Host "[5/6] Generating C# DLL..." -ForegroundColor Cyan

$blobFile = Join-Path $env:TEMP "kingdomco_encrypted.dat"
[IO.File]::WriteAllBytes($blobFile, $encryptedBlob)

$csSource = @'
using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Reflection;

namespace KingdomCo.Engine
{
    public class Engine
    {
        private static readonly string[] SaltNames = new string[] {
            "KingdomCo-L1-AES2-2026",
            "KingdomCo-L2-XOR2-2026",
            "KingdomCo-L3-AES2-2026",
            "KingdomCo-L4-XOR2-2026",
            "KingdomCo-L5-AES2-2026",
            "KingdomCo-L6-XOR2-2026"
        };

        private static byte[] DeriveKey(string passphrase, string salt, int iterations, int keySize)
        {
            using (var kdf = new Rfc2898DeriveBytes(passphrase, Encoding.UTF8.GetBytes(salt), iterations, HashAlgorithmName.SHA512))
            {
                return kdf.GetBytes(keySize);
            }
        }

        private static byte[] AESDecrypt(byte[] data, byte[] key)
        {
            using (var aes = Aes.Create())
            {
                aes.Key = key;
                byte[] iv = new byte[16];
                byte[] cipher = new byte[data.Length - 16];
                Buffer.BlockCopy(data, 0, iv, 0, 16);
                Buffer.BlockCopy(data, 16, cipher, 0, cipher.Length);
                aes.IV = iv;
                using (var decryptor = aes.CreateDecryptor())
                {
                    return decryptor.TransformFinalBlock(cipher, 0, cipher.Length);
                }
            }
        }

        private static byte[] AESEncrypt(byte[] data, byte[] key)
        {
            using (var aes = Aes.Create())
            {
                aes.Key = key;
                aes.GenerateIV();
                using (var encryptor = aes.CreateEncryptor())
                {
                    byte[] cipher = encryptor.TransformFinalBlock(data, 0, data.Length);
                    byte[] result = new byte[aes.IV.Length + cipher.Length];
                    Buffer.BlockCopy(aes.IV, 0, result, 0, aes.IV.Length);
                    Buffer.BlockCopy(cipher, 0, result, aes.IV.Length, cipher.Length);
                    return result;
                }
            }
        }

        private static byte[] XORTransform(byte[] data, byte[] key)
        {
            byte[] result = new byte[data.Length];
            for (int i = 0; i < data.Length; i++)
            {
                result[i] = (byte)(data[i] ^ key[i % key.Length]);
            }
            return result;
        }

        private static byte[] GetEmbeddedResource()
        {
            var asm = Assembly.GetExecutingAssembly();
            string resourceName = asm.GetManifestResourceNames()
                .FirstOrDefault(r => r.EndsWith(".dat"));
            if (resourceName == null)
                throw new Exception("Encrypted data not found in assembly.");
            using (var stream = asm.GetManifestResourceStream(resourceName))
            using (var ms = new MemoryStream())
            {
                stream.CopyTo(ms);
                return ms.ToArray();
            }
        }

        public static byte[] DecryptBlob(string passphrase)
        {
            byte[] encryptedBlob = GetEmbeddedResource();
            if (encryptedBlob == null || encryptedBlob.Length == 0)
                throw new Exception("Embedded blob is empty.");

            byte[] key1 = DeriveKey(passphrase, SaltNames[0], 100000, 32);
            byte[] key2 = DeriveKey(passphrase, SaltNames[1], 100000, 32);
            byte[] key3 = DeriveKey(passphrase, SaltNames[2], 100000, 32);
            byte[] key4 = DeriveKey(passphrase, SaltNames[3], 100000, 32);
            byte[] key5 = DeriveKey(passphrase, SaltNames[4], 100000, 32);
            byte[] key6 = DeriveKey(passphrase, SaltNames[5], 100000, 32);

            // Layer 6 reverse: XOR
            byte[] step6 = XORTransform(encryptedBlob, key6);
            // Layer 5 reverse: AES decrypt
            byte[] step5 = AESDecrypt(step6, key5);
            // Layer 4 reverse: XOR
            byte[] step4 = XORTransform(step5, key4);
            // Layer 3 reverse: AES decrypt
            byte[] step3 = AESDecrypt(step4, key3);
            // Layer 2 reverse: XOR
            byte[] step2 = XORTransform(step3, key2);
            // Layer 1 reverse: AES decrypt
            byte[] step1 = AESDecrypt(step2, key1);

            return step1;
        }

        public static void ExtractAll(string passphrase, string outputDir)
        {
            byte[] blob = DecryptBlob(passphrase);
            if (blob == null || blob.Length < 4)
                throw new Exception("Decrypted blob is invalid.");

            using (var ms = new MemoryStream(blob))
            using (var reader = new BinaryReader(ms))
            {
                int fileCount = reader.ReadInt32();
                for (int i = 0; i < fileCount; i++)
                {
                    short nameLen = reader.ReadInt16();
                    byte[] nameBytes = reader.ReadBytes(nameLen);
                    string filename = Encoding.UTF8.GetString(nameBytes);
                    int dataLen = reader.ReadInt32();
                    byte[] fileData = reader.ReadBytes(dataLen);

                    string fullPath = Path.Combine(outputDir, filename);
                    string dir = Path.GetDirectoryName(fullPath);
                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                        Directory.CreateDirectory(dir);

                    File.WriteAllBytes(fullPath, fileData);
                }
            }
        }

        public static string GetFileText(string passphrase, string targetFilename)
        {
            byte[] blob = DecryptBlob(passphrase);
            using (var ms = new MemoryStream(blob))
            using (var reader = new BinaryReader(ms))
            {
                int fileCount = reader.ReadInt32();
                for (int i = 0; i < fileCount; i++)
                {
                    short nameLen = reader.ReadInt16();
                    byte[] nameBytes = reader.ReadBytes(nameLen);
                    string filename = Encoding.UTF8.GetString(nameBytes);
                    int dataLen = reader.ReadInt32();
                    byte[] fileData = reader.ReadBytes(dataLen);

                    if (filename.Equals(targetFilename, StringComparison.OrdinalIgnoreCase))
                    {
                        return Encoding.UTF8.GetString(fileData);
                    }
                }
            }
            return null;
        }

        public static bool VerifyPassphrase(string passphrase)
        {
            try
            {
                byte[] blob = DecryptBlob(passphrase);
                return blob != null && blob.Length > 4;
            }
            catch { return false; }
        }

        public static string[] ListFiles(string passphrase)
        {
            byte[] blob = DecryptBlob(passphrase);
            var result = new System.Collections.Generic.List<string>();
            using (var ms = new MemoryStream(blob))
            using (var reader = new BinaryReader(ms))
            {
                int fileCount = reader.ReadInt32();
                for (int i = 0; i < fileCount; i++)
                {
                    short nameLen = reader.ReadInt16();
                    byte[] nameBytes = reader.ReadBytes(nameLen);
                    string filename = Encoding.UTF8.GetString(nameBytes);
                    int dataLen = reader.ReadInt32();
                    reader.ReadBytes(dataLen);
                    result.Add(string.Format("{0} ({1} bytes)", filename, dataLen));
                }
            }
            return result.ToArray();
        }

        public static string GetPassphrase()
        {
            byte[] p1 = Convert.FromBase64String("__P1__");
            byte[] p2 = Convert.FromBase64String("__P2__");
            byte[] mask = new byte[] { __MASK__ };
            byte[] combined = new byte[p1.Length + p2.Length];
            Buffer.BlockCopy(p1, 0, combined, 0, p1.Length);
            Buffer.BlockCopy(p2, 0, combined, p1.Length, p2.Length);
            for (int i = 0; i < combined.Length; i++)
            {
                combined[i] ^= mask[i % mask.Length];
            }
            return Encoding.UTF8.GetString(combined);
        }
    }
}
'@

$csReplaced = $csSource -replace '__P1__', $csP1 -replace '__P2__', $csP2 -replace '__MASK__', $csMask
$csFile = Join-Path $env:TEMP "KingdomCo.Engine.cs"
$csReplaced | Out-File $csFile -Encoding UTF8

$dllName = "KingdomCo.Engine.dll"
$dllPath = Join-Path $OutputDir $dllName
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

Write-Host "  Compiling DLL..." -ForegroundColor DarkGray
$args = @(
    "/target:library",
    "/out:$dllPath",
    "/resource:$blobFile",
    "/reference:System.Core.dll",
    $csFile
)

$output = & $csc $args 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Compilation failed!" -ForegroundColor Red
    Write-Host $output
    exit 1
}

$desktop = [Environment]::GetFolderPath("Desktop")
$desktopDll = Join-Path $desktop $dllName
Copy-Item $dllPath $desktopDll -Force

Write-Host "  DLL: $dllPath" -ForegroundColor Green
Write-Host "  DLL (desktop): $desktopDll" -ForegroundColor Green

# ============================================================
# TEST (using embedded GetPassphrase)
# ============================================================
Write-Host ""
Write-Host "=== TESTING DLL ===" -ForegroundColor Cyan

[Reflection.Assembly]::LoadFile($dllPath) | Out-Null
$testPass = [KingdomCo.Engine.Engine]::GetPassphrase()
$verify = [KingdomCo.Engine.Engine]::VerifyPassphrase($testPass)
if ($verify) {
    Write-Host "GetPassphrase + Verify: PASS" -ForegroundColor Green
} else {
    Write-Host "GetPassphrase + Verify: FAIL" -ForegroundColor Red
    exit 1
}

$fileList = [KingdomCo.Engine.Engine]::ListFiles($testPass)
Write-Host "Files ($($fileList.Length)):" -ForegroundColor Cyan
$fileList | % { Write-Host "  $_" -ForegroundColor DarkGray }

# Test extract
$tempExtract = Join-Path $env:TEMP "rok_engine_test"
if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
Write-Host "Extracting to $tempExtract ..." -ForegroundColor DarkGray
[KingdomCo.Engine.Engine]::ExtractAll($testPass, $tempExtract)
$extractCount = (Get-ChildItem $tempExtract -Recurse -File).Count
Write-Host "Extracted $extractCount files" -ForegroundColor Green
Remove-Item $tempExtract -Recurse -Force

Write-Host ""
Write-Host "  +--------------------------------------------+" -ForegroundColor Green
Write-Host "  |          BUILD COMPLETE!                    |" -ForegroundColor Green
Write-Host "  |  DLL:    $dllName" -ForegroundColor Green
Write-Host "  |  Layers: 6 (AES-XOR-AES-XOR-AES-XOR)" -ForegroundColor Green
Write-Host "  |  KDF:    100000x SHA512" -ForegroundColor Green
Write-Host "  |  Files:  $($fileList.Length)" -ForegroundColor Green
Write-Host "  |  No key.bin - passphrase in C# code" -ForegroundColor Green
Write-Host "  |  No KingROK.ps1 - Start.bat loads DLL" -ForegroundColor Green
Write-Host "  +--------------------------------------------+" -ForegroundColor Green
