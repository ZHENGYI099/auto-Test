# Auto-Test V2 Desktop Client - Quick Start Guide

## 🚀 Quick Launch

### Option 1: Double-click Launcher (Recommended)
Simply double-click: **`启动测试客户端.bat`**

### Option 2: Command Line
```bash
cd d:\auto-Test\auto-test-v2
python gui_client.py
```

---

## 📋 What You'll See

```
┌─────────────────────────────────────────────────────────┐
│ Auto-Test V2 - Automated Testing Client                │
├─────────────────────────────────────────────────────────┤
│ 📋 Auto-Test V2                                         │
│ Automated Test Script Generation & Execution Tool      │
├─────────────────────────────────────────────────────────┤
│ 🗂️ Step 1: Select CSV Test File                        │
│ CSV File: [_______________________________] [Browse...] │
│ Test Case ID: [______________] (optional)               │
├─────────────────────────────────────────────────────────┤
│ ⚙️ Step 2: Generate & Execute Test                     │
│ [📝 Generate Script] [▶️ Run Test] [⏹️ Stop] [📂 Open Dir] │
│ Status: Ready                                           │
│ Progress: [████████████████] 100%                       │
├─────────────────────────────────────────────────────────┤
│ 📊 Real-time Output Log                                 │
│ ┌───────────────────────────────────────────────────┐   │
│ │ [12:34:56] ✅ Test script generation completed!  │   │
│ │ [12:35:10] 🚀 Starting test execution...         │   │
│ │ [12:35:45] ✅ Passed: 12                         │   │
│ │ [12:35:45] ❌ Failed: 1                          │   │
│ └───────────────────────────────────────────────────┘   │
│                                          [Clear Log]     │
└─────────────────────────────────────────────────────────┘
```

---

## ⚡ 3-Step Workflow

### Step 1️⃣: Select CSV File
1. Click **[Browse...]** button
2. Choose your CSV test file (e.g., `case2test.csv`)
3. Test Case ID is auto-extracted (can be edited)

### Step 2️⃣: Generate Script
1. Click **[📝 Generate Script]**
2. Wait 10-30 seconds for AI processing
3. Script saved to `output/` folder

### Step 3️⃣: Run Test
1. Click **[▶️ Run Test (Admin)]**
2. Accept UAC prompt (Administrator rights required)
3. Watch real-time output in PowerShell window
4. View summary in the log panel

---

## 🎨 Log Color Guide

- 🔵 **Blue** = Information
- 🟢 **Green** = Success
- 🔴 **Red** = Error/Failure
- 🟠 **Orange** = Warning
- **Green Bold** = Test PASSED
- **Red Bold** = Test FAILED

---

## 🎯 Key Features

✅ **Drag & Drop CSV Upload** - Easy file selection  
✅ **AI-Powered Script Generation** - Azure OpenAI GPT-4  
✅ **Admin Execution** - One-click elevated execution  
✅ **Real-time Status** - Live progress tracking  
✅ **Result Summary** - Automatic pass/fail statistics  
✅ **Output Management** - Quick access to generated files  

---

## 🔧 Requirements

- **Python 3.8+**
- **Windows 10/11**
- **Dependencies**: `pip install -r requirements.txt`
- **Azure OpenAI Access** (configured in `.env`)

---

## 📁 Output Files

After execution, check `output/` directory for:

- `test_case{id}test.ps1` - Generated PowerShell script
- `{id}_*_VerifyResult.json` - Test results (JSON format)
- `case{id}test.json` - Intermediate JSON (if --keep-json)

---

## ❓ Troubleshooting

### Issue: "Module not found" error
**Solution**: Ensure you're running from `auto-test-v2` directory
```bash
cd d:\auto-Test\auto-test-v2
python gui_client.py
```

### Issue: UAC prompt doesn't appear
**Solution**: Try running the launcher as administrator

### Issue: Script generation is slow
**Answer**: Normal! AI generation takes 10-30 seconds

### Issue: Where are test results?
**Solution**: Click **[📂 Open Output Dir]** to view all files

---

## 🆚 CLI vs GUI Comparison

| Feature | CLI Version | Desktop Client |
|---------|------------|----------------|
| CSV Selection | Manual path | ✅ Graphical picker |
| Progress Display | Basic text | ✅ Progress bar + colors |
| Test Execution | Manual command | ✅ One-click execution |
| Result Viewing | Open file manually | ✅ Auto-summary |
| User Experience | ⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 📞 Need Help?

1. Check the **Real-time Output Log** for error details
2. Review generated script in `output/` folder
3. Verify Azure OpenAI configuration in `.env` file
4. Ensure all dependencies are installed: `pip install -r requirements.txt`

---

## 🎉 Enjoy Automated Testing!

The GUI makes your testing workflow **10x faster** and **100x easier**!

---

**Created:** October 2025  
**Version:** 2.0  
**Framework:** Python + Tkinter + Azure OpenAI
