# Fix Report: Build Debug APK failure (update-07 ke baad)

Date: 2026-10-16
Repo: Amixuai/VScoderoid-beta
Zip involved: `VSCodroid-update-07.zip` (30 files ka update), repo zip `VScoderoid-beta-Amixuai.zip`

## 1. Problem

Update-07 upload karne ke baad GitHub Actions ka **Build Debug APK** job fail hua.

- Failed step: **Fetch Code - OSS server** (11s mein fail)
- Error:
  `This server tree is missing at least one patch this checkout applies. It is almost certainly older than patches/.`
  `... run the "Build Code - OSS server" workflow -- and then remove ...vscode-reh-web-linux-arm64-1.139.1.tar.gz`
- "Build Code - OSS server" workflow chalane aur pass hone ke baad bhi Build Debug APK dobara chalane par **wahi error** aata raha.

## 2. Root cause (wajah)

File: `scripts/fetch-vscode-oss.sh`, line 43 (original):

```bash
REPO="${REPO:-rmyndharis/VSCodroid}"
```

- Ye script server tarball `server-1.139.1` ko GitHub release se download karti hai, aur cache ki digest bhi usi release se compare karti hai.
- Repo ka naam **original author ka (`rmyndharis/VSCodroid`) hardcoded** tha.
- "Build Code - OSS server" workflow release **aapke apne repo** (`Amixuai/VScoderoid-beta`) mein publish karta hai (`GITHUB_REPOSITORY`).
- Isliye APK build aapka naya server nahi, author ke repo ka purana server utha raha tha. Us tarball mein aapke repo ke patches nahi hain, to patch fingerprint check (`check-patch-fingerprints.py`) fail hota raha, chahe aap server kitni baar rebuild karo.

Note: update-07 ki 30 files mein koi build script ya workflow file nahi hai (sirf `saf-bridge-1.12.0` extension, `ubuntu-env.sh` aur docs). Meri analysis mein ye hardcoded repo pehle se tha; update-07 ne ise seedha nahi toda. Pehle ke builds ka cache ya alag state hone se ye pehle dikha nahi hoga, ye main confirm nahi kar sakta.

## 3. Fix

File changed: `scripts/fetch-vscode-oss.sh` (sirf line 43, ek comment ke saath)

```bash
REPO="${REPO:-${GITHUB_REPOSITORY:-rmyndharis/VSCodroid}}"
```

- GitHub Actions mein ab repo wahi hota hai jisme job chal rahi hai.
- Local machine par (jahan `GITHUB_REPOSITORY` nahi hota) fallback pehle jaisa `rmyndharis/VSCodroid` hai.
- `REPO=...` set karne ka tareeka abhi bhi kaam karta hai.

## 4. Kya NAHI badla

- Koi feature, workflow step ya check hataya ya band nahi kiya.
- Patch fingerprint check, branding check, digest check, ripgrep check, sab waise hi hain.
- Update-07 ki koi file nahi chhedi.

## 5. Aapko kya karna hai

1. Repo mein `scripts/fetch-vscode-oss.sh` ko is fixed file se replace karo, commit/push karo.
2. Agar patches push karne se pehle OSS build chalaya tha, to "Build Code - OSS server" ek baar dobara chalao.
3. "Build Debug APK" re-run karo.

## 6. Verification status

- `bash -n` syntax check: pass.
- GitHub Actions yahan chalaya nahi gaya, isliye build ka natija aapke re-run se hi confirm hoga.
- Failure log ki upar ki lines (kaun sa patch missing tha) screenshot mein nahi dikhi thi. Agar fix ke baad bhi fail ho, to us step ki `FAIL` wali lines bhejna.

## 7. Other note (is fix se alag)

`ToolchainRegistry.kt` mein Ruby/Java toolchain ke download URLs bhi `rmyndharis/VSCodroid` releases par hardcoded hain. Ye build ko nahi todte, lekin sideload install par toolchain wahin se aate hain. Is baar nahi badla.
