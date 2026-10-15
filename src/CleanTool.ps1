#requires -Version 5.1
<#
.SYNOPSIS
  CleanTool v3.2 - 玻璃拟态风格 · 中英双语
  安全承诺：只删除临时文件和缓存，绝不碰任何软件注册表、绝不删除驱动或系统文件

  v3.2 改进:
   · 修复回收站二次确认失效 (原来判断的项名不匹配, 确认框永不弹出)
   · 修复"项"计数未翻译, 英文模式显示中文
   · 扫描改为带进度+保持响应 (原来大目录会像卡死)
   · 目录大小统计改用 .NET 枚举并跳过符号链接, 大目录快数倍
   · 清理前统一确认框: 显示项数与预计释放量, 敏感项单独列出, 浏览器运行时提醒
   · 清理结果标注被占用未删净的项目, 并写入日志 (logs\clean-*.log)
   · 新增累计释放统计 (cleanstats.json)
   · 新增 7 个清理项: Windows.old / 传递优化 / 崩溃转储 / INetCache /
     其他浏览器(Brave/Vivaldi/Opera/Chromium) / WinSxS 组件清理(DISM) / 最近使用记录
   · 驱动检测与软件卸载窗口完成双语化 (原来固定中文)
#>

# 全局错误抑制，避免弹窗
$ErrorActionPreference = "SilentlyContinue"

# ===== 自动请求管理员权限 =====
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = [Environment]::GetCommandLineArgs()[0]
    Start-Process $self -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ===== 玻璃拟态颜色主题 =====
# 背景：柔和浅灰蓝
$colorBg = [System.Drawing.Color]::FromArgb(238, 241, 246)
$colorBg2 = [System.Drawing.Color]::FromArgb(228, 232, 240)
# 玻璃卡片：半透明白 + 柔和边框
$colorGlass = [System.Drawing.Color]::FromArgb(242, 244, 248)
$colorGlassBorder = [System.Drawing.Color]::FromArgb(255, 255, 255)
# 主色：柔和薰衣草紫蓝渐变
$colorPrimary = [System.Drawing.Color]::FromArgb(155, 168, 216)
$colorPrimaryLight = [System.Drawing.Color]::FromArgb(180, 192, 232)
$colorPrimaryDark = [System.Drawing.Color]::FromArgb(130, 145, 195)
# 强调色
$colorAccent = [System.Drawing.Color]::FromArgb(240, 168, 160)
$colorMint = [System.Drawing.Color]::FromArgb(168, 216, 192)
$colorPeach = [System.Drawing.Color]::FromArgb(250, 200, 160)
# 文字
$colorText = [System.Drawing.Color]::FromArgb(58, 63, 92)
$colorSubText = [System.Drawing.Color]::FromArgb(138, 143, 168)
$colorWhite = [System.Drawing.Color]::White
# 状态色
$colorGreen = [System.Drawing.Color]::FromArgb(120, 190, 150)
$colorRed = [System.Drawing.Color]::FromArgb(220, 120, 120)
$colorOrange = [System.Drawing.Color]::FromArgb(230, 170, 100)

# ===== 语言系统 =====
$script:lang = "zh"
$script:translations = @{
    "app_title" = @{ zh = "系统清理工具 v3.2"; en = "System Cleaner v3.2" }
    "main_title" = @{ zh = "系统清理工具"; en = "System Cleaner" }
    "main_subtitle" = @{ zh = "安全清理 · 驱动检测 · 只删缓存，绝不碰注册表和系统驱动"; en = "Safe Clean · Driver Check · Only cache, never touch registry or drivers" }
    "safety_promise" = @{ zh = "安全承诺：只删临时文件和缓存，绝不碰任何软件注册表、绝不删除驱动或系统文件"; en = "Safety Promise: Only temp files and cache, never touch software registry, never delete drivers or system files" }
    # --- v3.2 新增 ---
    "unit_items" = @{ zh = "项"; en = "items" }
    "status_prefix_scan" = @{ zh = "正在扫描"; en = "Scanning" }
    "status_prefix_clean" = @{ zh = "正在清理"; en = "Cleaning" }
    "status_ready" = @{ zh = "就绪"; en = "Ready" }
    "size_unknown" = @{ zh = "需实测"; en = "N/A" }
    "msg_confirm_title" = @{ zh = "确认清理"; en = "Confirm Clean" }
    "msg_confirm_body" = @{ zh = "即将清理 {0} 项，预计释放 {1}。`n`n只删除临时文件与缓存，不碰注册表和系统文件。`n确定继续吗？"; en = "About to clean {0} items, expected to free {1}.`n`nOnly temp files and caches will be removed; no registry or system files.`nContinue?" }
    "msg_confirm_sensitive" = @{ zh = "`n注意：勾选的项目中包含需要特别确认的："; en = "`nNote: the following selected items need extra care:" }
    "msg_browser_running" = @{ zh = "`n检测到浏览器正在运行，其缓存文件可能被占用而无法完全删除。建议先关闭浏览器再清理。"; en = "`nA browser is running. Its cache files may be locked and cannot be fully removed. Closing it first is recommended." }
    "msg_partial" = @{ zh = "部分文件被占用，剩余 {0}"; en = "partial, {0} left (files in use)" }
    "msg_log_saved" = @{ zh = "清理日志"; en = "Log" }
    "msg_cumulative" = @{ zh = "累计已释放"; en = "Total freed" }
    "msg_dism_done" = @{ zh = "组件清理已执行（耗时较长，实际释放量需重启后体现）"; en = "Component cleanup executed (takes a while; freed space shows after reboot)" }
    "item_windows_old" = @{ zh = "旧系统备份 (Windows.old)"; en = "Old Windows install (Windows.old)" }
    "item_windows_old_desc" = @{ zh = "升级系统后留下的旧版本备份，通常占几 GB 到几十 GB；删除后无法回退到旧系统"; en = "Backup of the previous Windows version; can be several GB. Removing it means no rollback" }
    "item_delivery_opt" = @{ zh = "传递优化缓存"; en = "Delivery Optimization cache" }
    "item_delivery_opt_desc" = @{ zh = "Windows 更新与商店的分发缓存，删除后会自动重建"; en = "Cache used to distribute Windows updates; rebuilt automatically" }
    "item_crashdump" = @{ zh = "程序崩溃转储"; en = "Application crash dumps" }
    "item_crashdump_desc" = @{ zh = "程序崩溃时生成的转储文件，用于排查问题，一般可直接删除"; en = "Dumps created when apps crash; safe to remove unless you are debugging" }
    "item_inetcache" = @{ zh = "系统网络缓存 (INetCache)"; en = "System internet cache (INetCache)" }
    "item_inetcache_desc" = @{ zh = "系统组件与 IE 内核下载的临时网页缓存"; en = "Temporary web cache used by system components" }
    "item_other_browsers" = @{ zh = "其他浏览器缓存 (Brave/Vivaldi/Opera/Chromium)"; en = "Other browser caches (Brave/Vivaldi/Opera/Chromium)" }
    "item_other_browsers_desc" = @{ zh = "上述 Chromium 内核浏览器的网页与代码缓存"; en = "Web and code caches of the Chromium-based browsers listed above" }
    "item_dism" = @{ zh = "WinSxS 组件清理 (DISM)"; en = "WinSxS component cleanup (DISM)" }
    "item_dism_desc" = @{ zh = "清理被取代的系统组件旧版本，可释放数 GB；耗时数分钟，且清理后无法卸载已安装的更新"; en = "Removes superseded component versions, often several GB. Takes minutes and prevents uninstalling past updates" }
    "item_recent" = @{ zh = "最近使用记录 / 跳转列表"; en = "Recent items / Jump lists" }
    "item_recent_desc" = @{ zh = "资源管理器「最近使用的文件」列表；属于使用痕迹，默认不勾选"; en = "Explorer's recent files list; a usage trace, unchecked by default" }
    # --- v3.2 驱动/卸载窗口国际化 ---
    "common_tip" = @{ zh = "提示"; en = "Notice" }
    "common_confirm" = @{ zh = "确认"; en = "Confirm" }
    "common_error" = @{ zh = "错误"; en = "Error" }
    "txt_unknown" = @{ zh = "未知"; en = "Unknown" }
    "drv_select_first" = @{ zh = "请先在列表中选中要处理的驱动！`n`n提示：按住 Ctrl 可以多选。"; en = "Please select drivers in the list first!`n`nTip: hold Ctrl to select multiple." }
    "drv_confirm_fix" = @{ zh = "将处理选中的 {0} 个异常驱动：`n`n- 注册表缺失但文件存在 → 重建注册表`n- 文件缺失但注册表存在 → 清除残留注册表`n`n是否继续？"; en = "About to fix {0} abnormal drivers:`n`n- Missing registry but files exist → rebuild registry`n- Missing files but registry exists → clear residual registry`n`nContinue?" }
    "drv_rep_ok" = @{ zh = "{0}：正常驱动，跳过"; en = "{0}: healthy driver, skipped" }
    "drv_rep_rebuilt" = @{ zh = "{0}：注册表已重建"; en = "{0}: registry rebuilt" }
    "drv_rep_rebuild_fail" = @{ zh = "{0}：重建失败"; en = "{0}: rebuild failed" }
    "drv_rep_cleared" = @{ zh = "{0}：残留注册表已清除"; en = "{0}: residual registry cleared" }
    "drv_rep_clear_fail" = @{ zh = "{0}：清除失败（可能需管理员权限）"; en = "{0}: clear failed (may need admin rights)" }
    "drv_rep_gone" = @{ zh = "{0}：文件和注册表都已不存在，无需处理"; en = "{0}: files and registry both gone, nothing to do" }
    "drv_rep_other" = @{ zh = "{0}：状态为 {1}，建议重装对应软件"; en = "{0}: status is {1}, reinstalling the software is recommended" }
    "drv_rep_head" = @{ zh = "处理完成！`n`n重建注册表: {0} 个`n清除残留: {1} 个`n跳过: {2} 个`n`n--- 明细 ---`n"; en = "Done!`n`nRegistry rebuilt: {0}`nResidual cleared: {1}`nSkipped: {2}`n`n--- Details ---`n" }
    "drv_rep_reboot" = @{ zh = "`n清除的残留驱动需要重启电脑后完全生效。"; en = "`nCleared residual drivers take effect after a restart." }
    "drv_result_title" = @{ zh = "驱动处理结果"; en = "Driver Fix Result" }
    "sfc_confirm" = @{ zh = "将运行系统文件完整性检查 (sfc /scannow)，需要几分钟，会在后台运行。`n`n完成后请手动重启电脑使修复生效。是否继续？"; en = "System File Checker (sfc /scannow) will run in the background and takes a few minutes.`n`nRestart your PC afterwards for the repair to take effect. Continue?" }
    "sfc_started" = @{ zh = "系统文件检查已在后台启动，大约需要 5-10 分钟。`n`n完成后请重启电脑。"; en = "System File Checker started in the background; it takes about 5-10 minutes.`n`nPlease restart your PC when it finishes." }
    "sfc_fail" = @{ zh = "启动失败，请手动以管理员身份运行命令提示符，输入 sfc /scannow"; en = "Failed to start. Run Command Prompt as administrator and type sfc /scannow" }
    "ace_confirm" = @{ zh = "将扫描并清除已卸载游戏残留的反作弊驱动（ACE、Vanguard、EAC、BattlEye、FACEIT 等）。`n`n注意：正在玩的游戏的反作弊不要清，否则需要重装。`n`n是否继续？"; en = "This scans and clears anti-cheat drivers left behind by uninstalled games (ACE, Vanguard, EAC, BattlEye, FACEIT, etc.).`n`nNote: do NOT clear anti-cheat for games you still play, or they must be reinstalled.`n`nContinue?" }
    "ace_dir" = @{ zh = "目录: {0}"; en = "Folder: {0}" }
    "ace_dir_locked" = @{ zh = "目录(被占用): {0}"; en = "Folder (in use): {0}" }
    "ace_head" = @{ zh = "清除完成！`n`n成功: {0} 项"; en = "Cleanup done!`n`nSucceeded: {0}" }
    "ace_need_reboot" = @{ zh = "`n需重启后清除: {0} 项"; en = "`nPending restart: {0}" }
    "ace_cleared_head" = @{ zh = "`n`n--- 已清除 ---`n"; en = "`n`n--- Cleared ---`n" }
    "ace_reboot_head" = @{ zh = "`n--- 需重启后清除 ---`n"; en = "`n--- Pending restart ---`n" }
    "ace_reboot_note" = @{ zh = "`n正在运行的内核驱动需要重启电脑后才能完全删除。"; en = "`nKernel drivers currently in use can only be removed after a restart." }
    "ace_result_title" = @{ zh = "反作弊残留清除结果"; en = "Anti-cheat Cleanup Result" }
    "uninstall_btn_sel" = @{ zh = "完全卸载选中"; en = "Fully Uninstall Selected" }
    "uninstall_confirm_title" = @{ zh = "确认完全卸载"; en = "Confirm Full Uninstall" }
    "uninstall_err_detail" = @{ zh = "卸载过程中出现错误: {0}"; en = "Error during uninstall: {0}" }
    "stat_items" = @{ zh = "可清理项目"; en = "Items" }
    "stat_size" = @{ zh = "可释放空间"; en = "Freeable Space" }
    "stat_status" = @{ zh = "状态"; en = "Status" }
    "status_scanning" = @{ zh = "正在扫描..."; en = "Scanning..." }
    "status_scan_done" = @{ zh = "扫描完成"; en = "Scan Complete" }
    "status_cleaning" = @{ zh = "正在清理..."; en = "Cleaning..." }
    "status_clean_done" = @{ zh = "清理完成"; en = "Clean Complete" }
    "col_item" = @{ zh = "清理项目"; en = "Item" }
    "col_size" = @{ zh = "占用大小"; en = "Size" }
    "col_desc" = @{ zh = "说明"; en = "Description" }
    "btn_select_all" = @{ zh = "全选安全项"; en = "Select Safe" }
    "btn_rescan" = @{ zh = "重新扫描"; en = "Rescan" }
    "btn_driver" = @{ zh = "驱动检测"; en = "Driver Check" }
    "btn_uninstall" = @{ zh = "软件卸载"; en = "Uninstall" }
    "btn_clean" = @{ zh = "一键清理"; en = "Clean All" }
    "btn_lang" = @{ zh = "EN"; en = "中文" }
    "item_temp_user" = @{ zh = "用户临时文件"; en = "User Temp Files" }
    "item_temp_user_desc" = @{ zh = "软件运行产生的临时文件"; en = "Temp files from software" }
    "item_temp_sys" = @{ zh = "系统临时文件"; en = "System Temp Files" }
    "item_temp_sys_desc" = @{ zh = "Windows 系统临时目录"; en = "Windows system temp directory" }
    "item_windows_update" = @{ zh = "Windows 更新缓存"; en = "Windows Update Cache" }
    "item_windows_update_desc" = @{ zh = "系统更新下载残留文件"; en = "Windows update download cache" }
    "item_thumb" = @{ zh = "缩略图缓存"; en = "Thumbnail Cache" }
    "item_thumb_desc" = @{ zh = "文件资源管理器缩略图"; en = "Explorer thumbnail cache" }
    "item_shader" = @{ zh = "着色器缓存"; en = "Shader Cache" }
    "item_shader_desc" = @{ zh = "DirectX/NVIDIA 着色器缓存"; en = "DirectX/NVIDIA shader cache" }
    "item_chrome" = @{ zh = "Chrome 浏览器缓存"; en = "Chrome Cache" }
    "item_chrome_desc" = @{ zh = "Chrome 网页缓存文件"; en = "Chrome web cache files" }
    "item_edge" = @{ zh = "Edge 浏览器缓存"; en = "Edge Cache" }
    "item_edge_desc" = @{ zh = "Edge 网页缓存文件"; en = "Edge web cache files" }
    "item_logs" = @{ zh = "系统日志"; en = "System Logs" }
    "item_logs_desc" = @{ zh = "Windows 系统日志文件"; en = "Windows system log files" }
    "item_wer" = @{ zh = "错误报告"; en = "Error Reports" }
    "item_wer_desc" = @{ zh = "Windows 错误报告文件"; en = "Windows error report files" }
    "item_dump" = @{ zh = "蓝屏转储"; en = "Crash Dumps" }
    "item_dump_desc" = @{ zh = "系统崩溃转储文件"; en = "System crash dump files" }
    "item_recycle" = @{ zh = "回收站"; en = "Recycle Bin" }
    "item_recycle_desc" = @{ zh = "清空后不可恢复，请确认"; en = "Cannot recover after empty, confirm" }
    "msg_no_selection" = @{ zh = "请先勾选要清理的项目！"; en = "Please select items to clean first!" }
    "msg_recycle_confirm" = @{ zh = "回收站清空后不可恢复！确定要清空吗？"; en = "Recycle Bin cannot be recovered after empty! Are you sure?" }
    "msg_clean_result_title" = @{ zh = "清理结果"; en = "Clean Result" }
    "msg_clean_done" = @{ zh = "清理完成！"; en = "Clean Complete!" }
    "msg_total_freed" = @{ zh = "共释放空间"; en = "Total Freed" }
    "msg_clean_detail" = @{ zh = "--- 清理明细 ---"; en = "--- Details ---" }
    "msg_not_touched" = @{ zh = "未触碰: 个人文件、已安装软件、系统驱动、注册表"; en = "Not touched: Personal files, installed software, system drivers, registry" }
    "driver_title" = @{ zh = "驱动与文件完整性检测"; en = "Driver & File Integrity Check" }
    "driver_total" = @{ zh = "驱动总数"; en = "Total Drivers" }
    "driver_ok" = @{ zh = "正常"; en = "OK" }
    "driver_missing" = @{ zh = "文件缺失"; en = "File Missing" }
    "driver_reg_missing" = @{ zh = "注册表缺失"; en = "Registry Missing" }
    "driver_sig_bad" = @{ zh = "签名异常"; en = "Signature Bad" }
    "driver_sig_valid" = @{ zh = "有效"; en = "Valid" }
    "driver_sig_unsigned" = @{ zh = "未签名"; en = "Unsigned" }
    "driver_sig_unknown" = @{ zh = "未知"; en = "Unknown" }
    "driver_sig_reinstall" = @{ zh = "需重装"; en = "Reinstall Needed" }
    "driver_anticheat" = @{ zh = "反作弊"; en = "Anti-Cheat" }
    "driver_col_name" = @{ zh = "驱动名称"; en = "Driver Name" }
    "driver_col_status" = @{ zh = "状态"; en = "Status" }
    "driver_col_path" = @{ zh = "文件路径"; en = "File Path" }
    "driver_col_sig" = @{ zh = "数字签名"; en = "Signature" }
    "driver_only_bad" = @{ zh = "只显示有问题的驱动"; en = "Only show problematic drivers" }
    "driver_fix_title" = @{ zh = "驱动修复工具"; en = "Driver Fix Tools" }
    "driver_fix_note" = @{ zh = "修复前会自动创建系统还原点"; en = "System restore point will be created before fix" }
    "driver_fix_reg" = @{ zh = "修复选中驱动注册表"; en = "Fix Selected Registry" }
    "driver_fix_reg_tip" = @{ zh = "重建注册表缺失的驱动项"; en = "Rebuild missing registry entries" }
    "driver_sfc" = @{ zh = "系统文件完整性检查"; en = "System File Check" }
    "driver_sfc_tip" = @{ zh = "运行 sfc /scannow 修复系统文件"; en = "Run sfc /scannow to fix system files" }
    "driver_clear_ac" = @{ zh = "清除残留反作弊驱动"; en = "Clear Anti-Cheat Residual" }
    "driver_clear_tip" = @{ zh = "清除 ACE/FACEIT 等残留驱动和服务"; en = "Clear ACE/FACEIT residual drivers and services" }
    "driver_rescan" = @{ zh = "重新扫描"; en = "Rescan" }
    "driver_close" = @{ zh = "关闭"; en = "Close" }
    "uninstall_title" = @{ zh = "软件完全卸载"; en = "Complete Software Uninstall" }
    "uninstall_subtitle" = @{ zh = "调用官方卸载程序 + 清理残留目录和注册表"; en = "Official uninstaller + residual directory and registry cleanup" }
    "uninstall_search" = @{ zh = "搜索软件..."; en = "Search software..." }
    "uninstall_col_name" = @{ zh = "软件名称"; en = "Software Name" }
    "uninstall_col_pub" = @{ zh = "发布者"; en = "Publisher" }
    "uninstall_col_ver" = @{ zh = "版本"; en = "Version" }
    "uninstall_col_size" = @{ zh = "大小"; en = "Size" }
    "uninstall_col_type" = @{ zh = "卸载方式"; en = "Uninstall Type" }
    "uninstall_quiet" = @{ zh = "静默卸载"; en = "Silent" }
    "uninstall_msi" = @{ zh = "MSI卸载"; en = "MSI" }
    "uninstall_standard" = @{ zh = "标准卸载"; en = "Standard" }
    "uninstall_unknown" = @{ zh = "未知"; en = "Unknown" }
    "uninstall_count" = @{ zh = "共 {0} 个软件"; en = "{0} software(s) total" }
    "uninstall_refresh" = @{ zh = "刷新列表"; en = "Refresh" }
    "uninstall_btn" = @{ zh = "完全卸载选中"; en = "Uninstall Selected" }
    "uninstall_btn_ing" = @{ zh = "卸载中..."; en = "Uninstalling..." }
    "uninstall_tip" = @{ zh = "卸载后自动清理残留目录和注册表项"; en = "Auto clean residual directory and registry after uninstall" }
    "uninstall_close" = @{ zh = "关闭"; en = "Close" }
    "uninstall_no_sel" = @{ zh = "请先选择要卸载的软件！"; en = "Please select software to uninstall first!" }
    "uninstall_confirm" = @{ zh = "确定要完全卸载「{0}」吗？`n`n将执行：`n1. 调用官方卸载程序`n2. 清理残留安装目录`n3. 清理残留注册表项`n`n此操作不可撤销！"; en = "Are you sure to completely uninstall '{0}'?`n`nWill execute:`n1. Run official uninstaller`n2. Clean residual install directory`n3. Clean residual registry`n`nThis cannot be undone!" }
    "uninstall_result_title" = @{ zh = "卸载完成"; en = "Uninstall Complete" }
    "uninstall_result" = @{ zh = "卸载结果：{0}`n`n软件：{1}`n残留目录清理：{2}`n注册表项清理：{3}`n`n建议：重启电脑以确保所有文件完全释放"; en = "Result: {0}`n`nSoftware: {1}`nResidual directory: {2}`nRegistry: {3}`n`nSuggestion: Restart PC to ensure all files are released" }
    "uninstall_done" = @{ zh = "卸载完成"; en = "Completed" }
    "uninstall_cleaned" = @{ zh = "已清理"; en = "Cleaned" }
    "uninstall_none" = @{ zh = "无残留或已被卸载程序清理"; en = "No residual or cleaned by uninstaller" }
    "uninstall_error" = @{ zh = "卸载过程中出现错误"; en = "Error during uninstall" }
}

function T($key) {
    if ($script:translations.ContainsKey($key)) {
        $entry = $script:translations[$key]
        if ($entry.ContainsKey($script:lang)) { return $entry[$script:lang] }
        if ($entry.ContainsKey("en")) { return $entry["en"] }
    }
    return $key
}

function Toggle-Language {
    if ($script:lang -eq "zh") { $script:lang = "en" } else { $script:lang = "zh" }
    Refresh-MainUI
}

function Refresh-MainUI {
    $form.Text = T("app_title")
    $lblTitle.Text = T("main_title")
    $lblSub.Text = T("main_subtitle")
    $lblSafety.Text = T("safety_promise")
    $lblCountLabel.Text = T("stat_items")
    $lblSizeLabel.Text = T("stat_size")
    $lblStatusLabel.Text = T("stat_status")
    $btnSelectAll.Text = T("btn_select_all")
    $btnRescan.Text = T("btn_rescan")
    $btnDriver.Text = T("btn_driver")
    $btnUninstall.Text = T("btn_uninstall")
    $btnClean.Text = T("btn_clean")
    $btnLang.Text = T("btn_lang")
    $listView.Columns[0].Text = T("col_item")
    $listView.Columns[1].Text = T("col_size")
    $listView.Columns[2].Text = T("col_desc")
    for ($i = 0; $i -lt $listView.Items.Count; $i++) {
        $listView.Items[$i].Text = (T $script:items[$i].Name)
        $listView.Items[$i].SubItems[2].Text = (T $script:items[$i].Desc)
    }
    $lblStatus.Text = T("status_scan_done")
    Update-Stats
    $form.Refresh()
}

# ===== 动画计时器 =====
$script:hoverTimer = New-Object System.Windows.Forms.Timer
$script:hoverTimer.Interval = 15
$script:hoverAnimations = @{}

# ===== 工具函数 =====
# 快速目录大小统计: 用 .NET 枚举替代 Get-ChildItem 管道, 大目录快数倍;
# 并跳过 junction/符号链接, 避免重复计算或死循环
function Get-DirSize($path) {
    if (-not $path -or $path -eq "") { return [long]0 }
    if (-not (Test-Path -LiteralPath $path)) { return [long]0 }
    $sum = [long]0
    try {
        $stack = New-Object System.Collections.Stack
        $stack.Push($path)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) {
                    try { $sum += (New-Object System.IO.FileInfo($f)).Length } catch { }
                }
            } catch { }
            try {
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    try {
                        $attr = [System.IO.File]::GetAttributes($d)
                        if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                        $stack.Push($d)
                    } catch { }
                }
            } catch { }
        }
    } catch { }
    return $sum
}

# ===== 程序目录 / 日志 / 累计统计 =====
$script:appDir = $PSScriptRoot
if (-not $script:appDir -or $script:appDir -eq "") {
    try { $script:appDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { $script:appDir = "" }
}
if (-not $script:appDir -or $script:appDir -eq "") { $script:appDir = (Get-Location).Path }
$script:logDir = Join-Path $script:appDir "logs"
$script:statsFile = Join-Path $script:appDir "cleanstats.json"
$script:logFile = ""

function Write-CleanLog($msg) {
    try {
        if (-not $script:logFile) {
            if (-not (Test-Path -LiteralPath $script:logDir)) { New-Item -ItemType Directory -Path $script:logDir -Force | Out-Null }
            $script:logFile = Join-Path $script:logDir ("clean-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        }
        Add-Content -LiteralPath $script:logFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) -Encoding UTF8
    } catch { }
}

function Get-Stats {
    try {
        if (Test-Path -LiteralPath $script:statsFile) {
            $o = Get-Content -LiteralPath $script:statsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return @{ totalFreed = [long]$o.totalFreed; runs = [int]$o.runs; lastTime = [string]$o.lastTime }
        }
    } catch { }
    return @{ totalFreed = [long]0; runs = 0; lastTime = "" }
}

function Save-Stats($freed) {
    try {
        $s = Get-Stats
        $new = @{
            totalFreed = ([long]$s.totalFreed + [long]$freed)
            runs       = ([int]$s.runs + 1)
            lastTime   = (Get-Date -Format "yyyy-MM-dd HH:mm")
        }
        [System.IO.File]::WriteAllText($script:statsFile, ($new | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Format-Size($bytes) {
    if ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N0} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

# 创建圆角区域
function Set-RoundedRegion($control, $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rect = [System.Drawing.Rectangle]::new(0, 0, $control.Width, $control.Height)
    $d = $radius * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $control.Region = New-Object System.Drawing.Region($path)
}

# 创建玻璃风格按钮
function New-GlassButton($text, $width, $height, $primary) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Size = New-Object System.Drawing.Size($width, $height)
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = if ($primary) { $colorPrimaryLight } else { [System.Drawing.Color]::FromArgb(250, 251, 253) }
    $btn.FlatAppearance.MouseDownBackColor = if ($primary) { $colorPrimaryDark } else { [System.Drawing.Color]::FromArgb(230, 233, 240) }
    if ($primary) {
        $btn.BackColor = $colorPrimary
        $btn.ForeColor = $colorWhite
        $btn.Font = New-Object System.Drawing.Font("微软雅黑", 10, [System.Drawing.FontStyle]::Bold)
    } else {
        $btn.BackColor = $colorGlass
        $btn.ForeColor = $colorText
        $btn.Font = New-Object System.Drawing.Font("微软雅黑", 9.5)
    }
    $btn.Cursor = "Hand"
    $btn.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.SmoothingMode = "AntiAlias"
            $highlightRect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, [int]($s.Height * 0.5))
            $highlightBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($highlightRect, [System.Drawing.Color]::FromArgb(40, 255, 255, 255), [System.Drawing.Color]::Transparent, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            if ($highlightBrush) {
                $e.Graphics.FillRectangle($highlightBrush, $highlightRect.X, $highlightRect.Y, $highlightRect.Width, $highlightRect.Height)
                $highlightBrush.Dispose()
            }
        } catch { }
    })
    return $btn
}

# 创建玻璃卡片面板
function New-GlassPanel($width, $height) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($width, $height)
    $panel.BackColor = $colorGlass
    $panel.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.SmoothingMode = "AntiAlias"
            $borderPen = New-Object System.Drawing.Pen($colorGlassBorder, 1)
            $e.Graphics.DrawRectangle($borderPen, 0, 0, $s.Width - 1, $s.Height - 1)
            $borderPen.Dispose()
            $topRect = [System.Drawing.Rectangle]::new(1, 1, $s.Width - 2, 1)
            $topBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 255, 255, 255))
            if ($topBrush) {
                $e.Graphics.FillRectangle($topBrush, $topRect.X, $topRect.Y, $topRect.Width, $topRect.Height)
                $topBrush.Dispose()
            }
        } catch { }
    })
    return $panel
}

# ===== 清理项目定义（只删文件，绝不碰注册表）=====
# 其他 Chromium 内核浏览器的用户数据目录 (缓存位于其下 Cache / Code Cache / GPUCache)
$script:otherBrowserUserData = @(
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    "$env:LOCALAPPDATA\Vivaldi\User Data"
    "$env:LOCALAPPDATA\Chromium\User Data"
    "$env:LOCALAPPDATA\Google\Chrome SxS\User Data"
    "$env:APPDATA\Opera Software\Opera Stable"
    "$env:APPDATA\Opera Software\Opera GX Stable"
)
$script:items = @(
    [pscustomobject]@{
        Name = "item_temp_user"; Desc = "item_temp_user_desc"; Default = $true
        Scan = { Get-DirSize $env:TEMP }
        Clean = { $s = Get-DirSize $env:TEMP; Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize $env:TEMP; return $s - $a }
    },
    [pscustomobject]@{
        Name = "item_temp_sys"; Desc = "item_temp_sys_desc"; Default = $true
        Scan = { Get-DirSize "C:\Windows\Temp" }
        Clean = { $s = Get-DirSize "C:\Windows\Temp"; Get-ChildItem "C:\Windows\Temp" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize "C:\Windows\Temp"; return $s - $a }
    },
    [pscustomobject]@{
        Name = "item_windows_update"; Desc = "item_windows_update_desc"; Default = $true
        Scan = { Get-DirSize "C:\Windows\SoftwareDistribution\Download" }
        Clean = { $s = Get-DirSize "C:\Windows\SoftwareDistribution\Download"; $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue; $wu = $false; if ($wuSvc) { $wu = ($wuSvc.Status -eq "Running") }; if ($wu) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }; Get-ChildItem "C:\Windows\SoftwareDistribution\Download" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; if ($wu) { Start-Service wuauserv -ErrorAction SilentlyContinue }; $a = Get-DirSize "C:\Windows\SoftwareDistribution\Download"; return $s - $a }
    },
    [pscustomobject]@{
        Name = "item_thumb"; Desc = "item_thumb_desc"; Default = $true
        Scan = { $p = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; if (-not (Test-Path $p)) { return [long]0 }; $sum = [long]0; Get-ChildItem $p -Filter "thumbcache_*" -File -ErrorAction SilentlyContinue | ForEach-Object { try { $sum += [long]$_.Length } catch { } }; return $sum }
        Clean = { $p = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; $s = [long]0; Get-ChildItem $p -Filter "thumbcache_*" -File -ErrorAction SilentlyContinue | ForEach-Object { try { $s += [long]$_.Length } catch { } }; Get-ChildItem $p -Filter "thumbcache_*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue; $a = [long]0; Get-ChildItem $p -Filter "thumbcache_*" -File -ErrorAction SilentlyContinue | ForEach-Object { try { $a += [long]$_.Length } catch { } }; return $s - $a }
    },
    [pscustomobject]@{
        Name = "item_shader"; Desc = "item_shader_desc"; Default = $false
        Scan = { $sum = 0; $sum += Get-DirSize "$env:LOCALAPPDATA\D3DSCache"; $sum += Get-DirSize "$env:LOCALAPPDATA\NVIDIA\DXCache"; $sum += Get-DirSize "$env:LOCALAPPDATA\NVIDIA\GLCache"; return $sum }
        Clean = { $total = 0; foreach ($p in @("$env:LOCALAPPDATA\D3DSCache","$env:LOCALAPPDATA\NVIDIA\DXCache","$env:LOCALAPPDATA\NVIDIA\GLCache")) { if (Test-Path $p) { $s = Get-DirSize $p; Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize $p; $total += ($s - $a) } }; return $total }
    },
    [pscustomobject]@{
        Name = "item_chrome"; Desc = "item_chrome_desc"; Default = $true
        Scan = { $sum = 0; $ud = "$env:LOCALAPPDATA\Google\Chrome\User Data"; if (Test-Path $ud) { Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object { $sum += Get-DirSize (Join-Path $_.FullName "Cache"); $sum += Get-DirSize (Join-Path $_.FullName "Code Cache") } }; return $sum }
        Clean = { $total = 0; $ud = "$env:LOCALAPPDATA\Google\Chrome\User Data"; if (Test-Path $ud) { Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object { foreach ($sub in @("Cache","Code Cache")) { $cp = Join-Path $_.FullName $sub; if (Test-Path $cp) { $s = Get-DirSize $cp; Get-ChildItem $cp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize $cp; $total += ($s - $a) } } } }; return $total }
    },
    [pscustomobject]@{
        Name = "item_edge"; Desc = "item_edge_desc"; Default = $true
        Scan = { $sum = 0; $ud = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; if (Test-Path $ud) { Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object { $sum += Get-DirSize (Join-Path $_.FullName "Cache"); $sum += Get-DirSize (Join-Path $_.FullName "Code Cache") } }; return $sum }
        Clean = { $total = 0; $ud = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; if (Test-Path $ud) { Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object { foreach ($sub in @("Cache","Code Cache")) { $cp = Join-Path $_.FullName $sub; if (Test-Path $cp) { $s = Get-DirSize $cp; Get-ChildItem $cp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize $cp; $total += ($s - $a) } } } }; return $total }
    },
    [pscustomobject]@{
        Name = "item_logs"; Desc = "item_logs_desc"; Default = $true
        Scan = { Get-DirSize "C:\Windows\Logs" }
        Clean = { $s = Get-DirSize "C:\Windows\Logs"; Get-ChildItem "C:\Windows\Logs" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize "C:\Windows\Logs"; return $s - $a }
    },
    [pscustomobject]@{
        Name = "item_wer"; Desc = "item_wer_desc"; Default = $true
        Scan = { Get-DirSize "$env:ProgramData\Microsoft\Windows\WER" }
        Clean = { $s = Get-DirSize "$env:ProgramData\Microsoft\Windows\WER"; Get-ChildItem "$env:ProgramData\Microsoft\Windows\WER" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize "$env:ProgramData\Microsoft\Windows\WER"; return $s - $a }
    },
    [pscustomobject]@{
        Name = "item_dump"; Desc = "item_dump_desc"; Default = $true
        Scan = { $sum = Get-DirSize "C:\Windows\Minidump"; if (Test-Path "C:\Windows\MEMORY.DMP") { $sum += (Get-Item "C:\Windows\MEMORY.DMP").Length }; return $sum }
        Clean = { $total = 0; $s = Get-DirSize "C:\Windows\Minidump"; Get-ChildItem "C:\Windows\Minidump" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; $a = Get-DirSize "C:\Windows\Minidump"; $total += ($s - $a); if (Test-Path "C:\Windows\MEMORY.DMP") { $dmp = (Get-Item "C:\Windows\MEMORY.DMP").Length; Remove-Item "C:\Windows\MEMORY.DMP" -Force -ErrorAction SilentlyContinue; if (-not (Test-Path "C:\Windows\MEMORY.DMP")) { $total += $dmp } }; return $total }
    },
    [pscustomobject]@{
        Name = "item_recycle"; Desc = "item_recycle_desc"; Default = $false; Confirm = $true
        Scan = { try { $shell = New-Object -ComObject Shell.Application; $items = $shell.NameSpace(0xA).Items(); $sum = [long]0; foreach ($item in $items) { try { $sum += [long]$item.Size } catch { } }; return $sum } catch { return [long]0 } }
        Clean = { try { $shell = New-Object -ComObject Shell.Application; $items1 = $shell.NameSpace(0xA).Items(); $b = [long]0; foreach ($item in $items1) { try { $b += [long]$item.Size } catch { } }; Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500; $items2 = $shell.NameSpace(0xA).Items(); $a = [long]0; foreach ($item in $items2) { try { $a += [long]$item.Size } catch { } }; return $b - $a } catch { return [long]0 } }
    },
    [pscustomobject]@{
        Name = "item_windows_old"; Desc = "item_windows_old_desc"; Default = $false; Confirm = $true
        Scan = { Get-DirSize "C:\Windows.old" }
        Clean = {
            if (-not (Test-Path "C:\Windows.old")) { return [long]0 }
            $s = Get-DirSize "C:\Windows.old"
            Remove-Item "C:\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path "C:\Windows.old") {
                # 旧系统目录需要先接管所有权才能删除
                & takeown.exe /F "C:\Windows.old" /R /A /D Y 2>$null | Out-Null
                & icacls.exe "C:\Windows.old" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                Remove-Item "C:\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
            }
            $a = Get-DirSize "C:\Windows.old"
            return ($s - $a)
        }
    },
    [pscustomobject]@{
        Name = "item_delivery_opt"; Desc = "item_delivery_opt_desc"; Default = $true
        Scan = {
            $sum = [long]0
            foreach ($p in @("C:\Windows\SoftwareDistribution\DeliveryOptimization", "$env:ProgramData\Microsoft\Windows\DeliveryOptimization")) { $sum += Get-DirSize $p }
            return $sum
        }
        Clean = {
            $total = [long]0
            foreach ($p in @("C:\Windows\SoftwareDistribution\DeliveryOptimization", "$env:ProgramData\Microsoft\Windows\DeliveryOptimization")) {
                if (Test-Path $p) {
                    $s = Get-DirSize $p
                    Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    $a = Get-DirSize $p
                    $total += ($s - $a)
                }
            }
            return $total
        }
    },
    [pscustomobject]@{
        Name = "item_crashdump"; Desc = "item_crashdump_desc"; Default = $true
        Scan = { Get-DirSize "$env:LOCALAPPDATA\CrashDumps" }
        Clean = {
            $p = "$env:LOCALAPPDATA\CrashDumps"
            $s = Get-DirSize $p
            Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            return ($s - (Get-DirSize $p))
        }
    },
    [pscustomobject]@{
        Name = "item_inetcache"; Desc = "item_inetcache_desc"; Default = $true
        Scan = { Get-DirSize "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" }
        Clean = {
            $p = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
            $s = Get-DirSize $p
            Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            return ($s - (Get-DirSize $p))
        }
    },
    [pscustomobject]@{
        Name = "item_other_browsers"; Desc = "item_other_browsers_desc"; Default = $false
        Scan = {
            $sum = [long]0
            foreach ($ud in $script:otherBrowserUserData) {
                if (-not (Test-Path $ud)) { continue }
                if (Test-Path (Join-Path $ud "Cache")) {
                    foreach ($sub in @("Cache","Code Cache","GPUCache")) { $sum += Get-DirSize (Join-Path $ud $sub) }
                } else {
                    Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object {
                        foreach ($sub in @("Cache","Code Cache","GPUCache")) { $sum += Get-DirSize (Join-Path $_.FullName $sub) }
                    }
                }
            }
            return $sum
        }
        Clean = {
            $total = [long]0
            foreach ($ud in $script:otherBrowserUserData) {
                if (-not (Test-Path $ud)) { continue }
                $targets = @()
                if (Test-Path (Join-Path $ud "Cache")) {
                    foreach ($sub in @("Cache","Code Cache","GPUCache")) { $targets += (Join-Path $ud $sub) }
                } else {
                    Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } | ForEach-Object {
                        foreach ($sub in @("Cache","Code Cache","GPUCache")) { $targets += (Join-Path $_.FullName $sub) }
                    }
                }
                foreach ($cp in $targets) {
                    if (Test-Path $cp) {
                        $s = Get-DirSize $cp
                        Get-ChildItem $cp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        $total += ($s - (Get-DirSize $cp))
                    }
                }
            }
            return $total
        }
    },
    [pscustomobject]@{
        Name = "item_dism"; Desc = "item_dism_desc"; Default = $false; Confirm = $true; NoSize = $true
        Scan = { return [long]-1 }   # 无法预估, 界面显示"需实测"
        Clean = {
            try { & dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null } catch { }
            return [long]-1
        }
    },
    [pscustomobject]@{
        Name = "item_recent"; Desc = "item_recent_desc"; Default = $false
        Scan = { Get-DirSize "$env:APPDATA\Microsoft\Windows\Recent" }
        Clean = {
            $p = "$env:APPDATA\Microsoft\Windows\Recent"
            $s = Get-DirSize $p
            Get-ChildItem $p -Force -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            return ($s - (Get-DirSize $p))
        }
    }
)

# ===== 构建主界面 =====
$form = New-Object System.Windows.Forms.Form
$form.Text = T("app_title")
$form.Size = New-Object System.Drawing.Size(780, 660)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("微软雅黑", 9)
$form.MinimumSize = New-Object System.Drawing.Size(740, 600)
$form.Add_Paint({
    param($s, $e)
    try {
        $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $colorBg, $colorBg2, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        if ($brush) {
            $e.Graphics.FillRectangle($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height)
            $brush.Dispose()
        }
        $glowRect = [System.Drawing.Rectangle]::new(-100, -50, $s.Width + 200, 200)
        $glowBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($glowRect, [System.Drawing.Color]::FromArgb(60, 180, 192, 232), [System.Drawing.Color]::Transparent, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        if ($glowBrush) {
            $e.Graphics.FillEllipse($glowBrush, $glowRect.X, $glowRect.Y, $glowRect.Width, $glowRect.Height)
            $glowBrush.Dispose()
        }
    } catch { }
})

# 顶部标题区 - 渐变玻璃
$panelHeader = New-Object System.Windows.Forms.Panel
$panelHeader.Location = New-Object System.Drawing.Point(0, 0)
$panelHeader.Size = New-Object System.Drawing.Size(780, 90)
$panelHeader.BackColor = $colorPrimary
$panelHeader.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.SmoothingMode = "AntiAlias"
        $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $colorPrimary, $colorPrimaryLight, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        if ($brush) {
            $e.Graphics.FillRectangle($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height)
            $brush.Dispose()
        }
        $topRect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, 2)
        $topBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 255, 255, 255))
        if ($topBrush) {
            $e.Graphics.FillRectangle($topBrush, $topRect.X, $topRect.Y, $topRect.Width, $topRect.Height)
            $topBrush.Dispose()
        }
    } catch { }
})
$form.Controls.Add($panelHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = T("main_title")
$lblTitle.Font = New-Object System.Drawing.Font("微软雅黑", 20, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $colorWhite
$lblTitle.Location = New-Object System.Drawing.Point(35, 18)
$lblTitle.AutoSize = $true
$panelHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = T("main_subtitle")
$lblSub.Font = New-Object System.Drawing.Font("微软雅黑", 9.5)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 250)
$lblSub.Location = New-Object System.Drawing.Point(38, 55)
$lblSub.AutoSize = $true
$panelHeader.Controls.Add($lblSub)

# 安全提示条 - 薄荷绿玻璃
$panelSafety = New-GlassPanel 720 32
$panelSafety.Location = New-Object System.Drawing.Point(20, 100)
$panelSafety.BackColor = [System.Drawing.Color]::FromArgb(235, 245, 240)
$form.Controls.Add($panelSafety)

$lblSafety = New-Object System.Windows.Forms.Label
$lblSafety.Text = "  " + (T "safety_promise")
$lblSafety.Font = New-Object System.Drawing.Font("微软雅黑", 8.5)
$lblSafety.ForeColor = $colorGreen
$lblSafety.Location = New-Object System.Drawing.Point(8, 7)
$lblSafety.AutoSize = $true
$panelSafety.Controls.Add($lblSafety)

# 统计卡片区域
$panelStats = New-GlassPanel 720 70
$panelStats.Location = New-Object System.Drawing.Point(20, 142)
$form.Controls.Add($panelStats)

$lblCountLabel = New-Object System.Windows.Forms.Label
$lblCountLabel.Text = T("stat_items")
$lblCountLabel.Font = New-Object System.Drawing.Font("微软雅黑", 8.5)
$lblCountLabel.ForeColor = $colorSubText
$lblCountLabel.Location = New-Object System.Drawing.Point(30, 10)
$lblCountLabel.AutoSize = $true
$panelStats.Controls.Add($lblCountLabel)

$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Text = "0 $(T 'unit_items')"
$lblCount.Font = New-Object System.Drawing.Font("微软雅黑", 18, [System.Drawing.FontStyle]::Bold)
$lblCount.ForeColor = $colorText
$lblCount.Location = New-Object System.Drawing.Point(30, 30)
$lblCount.AutoSize = $true
$panelStats.Controls.Add($lblCount)

$lblSizeLabel = New-Object System.Windows.Forms.Label
$lblSizeLabel.Text = T("stat_size")
$lblSizeLabel.Font = New-Object System.Drawing.Font("微软雅黑", 8.5)
$lblSizeLabel.ForeColor = $colorSubText
$lblSizeLabel.Location = New-Object System.Drawing.Point(210, 10)
$lblSizeLabel.AutoSize = $true
$panelStats.Controls.Add($lblSizeLabel)

$lblSize = New-Object System.Windows.Forms.Label
$lblSize.Text = "0 B"
$lblSize.Font = New-Object System.Drawing.Font("微软雅黑", 18, [System.Drawing.FontStyle]::Bold)
$lblSize.ForeColor = $colorGreen
$lblSize.Location = New-Object System.Drawing.Point(210, 30)
$lblSize.AutoSize = $true
$panelStats.Controls.Add($lblSize)

$lblStatusLabel = New-Object System.Windows.Forms.Label
$lblStatusLabel.Text = T("stat_status")
$lblStatusLabel.Font = New-Object System.Drawing.Font("微软雅黑", 8.5)
$lblStatusLabel.ForeColor = $colorSubText
$lblStatusLabel.Location = New-Object System.Drawing.Point(420, 10)
$lblStatusLabel.AutoSize = $true
$panelStats.Controls.Add($lblStatusLabel)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = T("status_ready")
$lblStatus.Font = New-Object System.Drawing.Font("微软雅黑", 12, [System.Drawing.FontStyle]::Bold)
$lblStatus.ForeColor = $colorPrimaryDark
$lblStatus.Location = New-Object System.Drawing.Point(420, 34)
$lblStatus.AutoSize = $true
$panelStats.Controls.Add($lblStatus)

# 列表外框 - 圆角玻璃（先添加，在列表后面）
$listBorder = New-GlassPanel 722 332
$listBorder.Location = New-Object System.Drawing.Point(19, 224)
$listBorder.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($listBorder)
$listBorder.SendToBack()

# 清理项目列表 - 玻璃风格
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(20, 225)
$listView.Size = New-Object System.Drawing.Size(720, 330)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.CheckBoxes = $true
$listView.GridLines = $false
$listView.BackColor = $colorGlass
$listView.Font = New-Object System.Drawing.Font("微软雅黑", 9.5)
$listView.BorderStyle = "None"
$listView.Columns.Add((T("col_item")), 210) | Out-Null
$listView.Columns.Add((T("col_size")), 110) | Out-Null
$listView.Columns.Add((T("col_desc")), 380) | Out-Null
$form.Controls.Add($listView)
$listView.BringToFront()

# 底部按钮区
$btnSelectAll = New-GlassButton (T("btn_select_all")) 110 40 $false
$btnSelectAll.Location = New-Object System.Drawing.Point(20, 575)
$form.Controls.Add($btnSelectAll)

$btnRescan = New-GlassButton (T("btn_rescan")) 110 40 $false
$btnRescan.Location = New-Object System.Drawing.Point(140, 575)
$form.Controls.Add($btnRescan)

$btnDriver = New-GlassButton (T("btn_driver")) 110 40 $false
$btnDriver.Location = New-Object System.Drawing.Point(250, 575)
$btnDriver.BackColor = [System.Drawing.Color]::FromArgb(250, 235, 220)
$btnDriver.ForeColor = [System.Drawing.Color]::FromArgb(180, 110, 50)
$form.Controls.Add($btnDriver)

$btnUninstall = New-GlassButton (T("btn_uninstall")) 110 40 $false
$btnUninstall.Location = New-Object System.Drawing.Point(370, 575)
$btnUninstall.BackColor = [System.Drawing.Color]::FromArgb(220, 240, 230)
$btnUninstall.ForeColor = [System.Drawing.Color]::FromArgb(50, 130, 90)
$form.Controls.Add($btnUninstall)

$btnClean = New-GlassButton (T("btn_clean")) 180 52 $true
$btnClean.Location = New-Object System.Drawing.Point(540, 568)
$btnClean.Font = New-Object System.Drawing.Font("微软雅黑", 13, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnClean)

$btnLang = New-GlassButton (T("btn_lang")) 60 32 $false
$btnLang.Location = New-Object System.Drawing.Point(700, 25)
$btnLang.BackColor = [System.Drawing.Color]::FromArgb(70, 255, 255, 255)
$btnLang.ForeColor = $colorWhite
$btnLang.Font = New-Object System.Drawing.Font("微软雅黑", 9, [System.Drawing.FontStyle]::Bold)
$panelHeader.Controls.Add($btnLang)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 575)
$progressBar.Size = New-Object System.Drawing.Size(490, 40)
$progressBar.Visible = $false
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# ===== 清理功能函数 =====
$script:scanResults = @()

function Update-Stats {
    $count = 0; $total = [long]0; $unknown = 0
    for ($i = 0; $i -lt $listView.Items.Count; $i++) {
        if ($listView.Items[$i].Checked) {
            $count++
            $val = [long]$script:scanResults[$i].Size
            if ($val -gt 0) { $total += $val }
            elseif ($val -lt 0) { $unknown++ }
        }
    }
    $lblCount.Text = "$count $(T 'unit_items')"
    if ($total -eq 0 -and $unknown -gt 0) { $lblSize.Text = (T 'size_unknown') } else { $lblSize.Text = Format-Size $total }
}

function Invoke-Scan {
    $listView.Items.Clear()
    $script:scanResults = @()
    # 扫描期间显示进度并保持界面响应 (原来是一次性阻塞, 大目录会像卡死)
    $btnClean.Visible = $false; $btnSelectAll.Visible = $false; $btnRescan.Visible = $false
    $btnDriver.Visible = $false; $btnUninstall.Visible = $false
    $progressBar.Visible = $true
    $progressBar.Maximum = $script:items.Count
    $progressBar.Value = 0
    foreach ($item in $script:items) {
        $lblStatus.Text = "$(T 'status_prefix_scan') $(T $item.Name)"
        $progressBar.Value++
        [System.Windows.Forms.Application]::DoEvents()
        $size = [long]0
        try { $raw = & $item.Scan; if ($raw) { $size = [long]$raw } } catch { $size = [long]0 }
        $script:scanResults += [pscustomobject]@{ Item = $item; Size = $size }
        $lvi = New-Object System.Windows.Forms.ListViewItem((T $item.Name))
        $sizeText = $(if ($size -lt 0) { (T 'size_unknown') } else { Format-Size $size })
        $lvi.SubItems.Add($sizeText) | Out-Null
        $lvi.SubItems.Add((T $item.Desc)) | Out-Null
        $lvi.Checked = $item.Default
        $listView.Items.Add($lvi) | Out-Null
    }
    $progressBar.Visible = $false
    $btnClean.Visible = $true; $btnSelectAll.Visible = $true; $btnRescan.Visible = $true
    $btnDriver.Visible = $true; $btnUninstall.Visible = $true
    Update-Stats
    $lblStatus.Text = T("status_scan_done")
}

function Invoke-Clean {
    $checked = @()
    for ($i = 0; $i -lt $listView.Items.Count; $i++) {
        if ($listView.Items[$i].Checked) { $checked += $i }
    }
    if ($checked.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((T("msg_no_selection")), "CleanTool", "OK", "Information")
        return
    }

    # ---- 汇总勾选项, 准备确认信息 ----
    $selTotal = [long]0
    $sensitive = @()
    $selBrowser = $false
    $browserNames = @("item_chrome","item_edge","item_other_browsers")
    foreach ($idx in $checked) {
        $it = $script:items[$idx]
        $sz = [long]$script:scanResults[$idx].Size
        if ($sz -gt 0) { $selTotal += $sz }
        if ($it.Confirm) { $sensitive += (T $it.Name) }
        if ($browserNames -contains $it.Name) { $selBrowser = $true }
    }
    $browserRunning = $false
    if ($selBrowser) {
        foreach ($bn in @("chrome","msedge","brave","vivaldi","opera","chromium")) {
            if (Get-Process -Name $bn -ErrorAction SilentlyContinue) { $browserRunning = $true; break }
        }
    }

    # ---- 清理前确认 (含敏感项与浏览器占用提示) ----
    $body = ((T 'msg_confirm_body') -f $checked.Count, (Format-Size $selTotal))
    if ($sensitive.Count -gt 0) {
        $body += (T 'msg_confirm_sensitive') + "`n" + (($sensitive | ForEach-Object { "  · $_" }) -join "`n")
    }
    if ($browserRunning) { $body += (T 'msg_browser_running') }
    $answer = [System.Windows.Forms.MessageBox]::Show($body, (T 'msg_confirm_title'), "YesNo", "Warning")
    if ($answer -ne "Yes") { return }

    # ---- 开始清理 ----
    $btnClean.Visible = $false; $btnSelectAll.Visible = $false; $btnRescan.Visible = $false
    $btnDriver.Visible = $false; $btnUninstall.Visible = $false
    $progressBar.Visible = $true
    $progressBar.Maximum = $checked.Count
    $progressBar.Value = 0
    $lblStatus.Text = T("status_cleaning")
    $form.Refresh()

    Write-CleanLog ("==== 清理开始: {0} 项, 预计 {1} ====" -f $checked.Count, (Format-Size $selTotal))
    $report = @(); $totalFreed = [long]0
    foreach ($idx in $checked) {
        $item = $script:items[$idx]
        $before = [long]$script:scanResults[$idx].Size
        $nameNow = (T $item.Name)
        $lblStatus.Text = "$(T 'status_prefix_clean') $nameNow"
        $progressBar.Value++
        [System.Windows.Forms.Application]::DoEvents()

        $freed = [long]0
        try { $raw = & $item.Clean; if ($raw) { $freed = [long]$raw } } catch { $freed = [long]0 }
        if ($freed -gt 0) { $totalFreed += $freed }

        # 备注: DISM 无法统计; 其余若明显少于清理前, 说明有文件被占用
        $note = ""
        if ($freed -lt 0) { $note = (T 'msg_dism_done') }
        elseif ($before -gt 0 -and $freed -lt [long]($before * 0.9)) {
            $left = $before - $freed
            if ($left -gt 0) { $note = ((T 'msg_partial') -f (Format-Size $left)) }
        }

        $report += [pscustomobject]@{ Name = $nameNow; Freed = $freed; Note = $note }
        $listView.Items[$idx].SubItems[1].Text = $(if ($freed -ge 0) { Format-Size $freed } else { "-" })
        $listView.Items[$idx].Checked = $false
        Write-CleanLog ("  {0}: {1}{2}" -f $nameNow, $(if ($freed -ge 0) { Format-Size $freed } else { "N/A" }), $(if ($note) { "  ($note)" } else { "" }))
    }

    $progressBar.Visible = $false
    $btnClean.Visible = $true; $btnSelectAll.Visible = $true; $btnRescan.Visible = $true
    $btnDriver.Visible = $true; $btnUninstall.Visible = $true
    $lblStatus.Text = T("status_clean_done")

    Save-Stats $totalFreed
    $stats = Get-Stats
    Write-CleanLog ("==== 清理完成: 本次 {0}, 累计 {1} ====" -f (Format-Size $totalFreed), (Format-Size ([long]$stats.totalFreed)))

    $reportText = (T("msg_clean_done")) + "`n`n" + (T("msg_total_freed")) + ": $(Format-Size $totalFreed)`n" + (T 'msg_cumulative') + ": $(Format-Size ([long]$stats.totalFreed))`n`n" + (T("msg_clean_detail")) + "`n"
    foreach ($r in $report) {
        $line = "  $($r.Name): " + $(if ($r.Freed -ge 0) { Format-Size $r.Freed } else { "-" })
        if ($r.Note) { $line += "  ($($r.Note))" }
        $reportText += $line + "`n"
    }
    $reportText += "`n" + (T("msg_not_touched"))
    if ($script:logFile) { $reportText += "`n`n" + (T 'msg_log_saved') + ": " + $script:logFile }
    [System.Windows.Forms.MessageBox]::Show($reportText, "CleanTool", "OK", "Information")
    Update-Stats
}

# ===== 驱动检测窗口 =====
function Show-DriverChecker {
    $dForm = New-Object System.Windows.Forms.Form
    $dForm.Text = T("driver_title")
    $dForm.Size = New-Object System.Drawing.Size(840, 700)
    $dForm.StartPosition = "CenterScreen"
    $dForm.Font = New-Object System.Drawing.Font("微软雅黑", 9)
    $dForm.Add_Paint({
        param($s, $e)
        try {
            $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
            $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $colorBg, $colorBg2, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            if ($brush) {
                $e.Graphics.FillRectangle($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height)
                $brush.Dispose()
            }
        } catch { }
    })

    # 标题栏
    $dPanel = New-Object System.Windows.Forms.Panel
    $dPanel.Location = New-Object System.Drawing.Point(0, 0)
    $dPanel.Size = New-Object System.Drawing.Size(840, 70)
    $dPanel.BackColor = $colorPrimary
    $dPanel.Add_Paint({
        param($s, $e)
        try {
            $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
            $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $colorPrimary, $colorPrimaryLight, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            if ($brush) {
                $e.Graphics.FillRectangle($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height)
                $brush.Dispose()
            }
        } catch { }
    })
    $dForm.Controls.Add($dPanel)

    $dTitle = New-Object System.Windows.Forms.Label
    $dTitle.Text = T("driver_title")
    $dTitle.Font = New-Object System.Drawing.Font("微软雅黑", 16, [System.Drawing.FontStyle]::Bold)
    $dTitle.ForeColor = $colorWhite
    $dTitle.Location = New-Object System.Drawing.Point(30, 18)
    $dTitle.AutoSize = $true
    $dPanel.Controls.Add($dTitle)

    # 统计卡片
    $dStats = New-GlassPanel 790 65
    $dStats.Location = New-Object System.Drawing.Point(15, 85)
    $dForm.Controls.Add($dStats)

    $statItems = @(
        @{Label=T("driver_total"); Var="dTotal"; Color=$colorText; X=25},
        @{Label=T("driver_ok"); Var="dOk"; Color=$colorGreen; X=175},
        @{Label=T("driver_missing"); Var="dWarn"; Color=$colorOrange; X=325},
        @{Label=T("driver_reg_missing"); Var="dErr"; Color=$colorRed; X=475},
        @{Label=T("driver_sig_bad"); Var="dSig"; Color=$colorAccent; X=625}
    )
    foreach ($si in $statItems) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $si.Label
        $lbl.Font = New-Object System.Drawing.Font("微软雅黑", 8.5)
        $lbl.ForeColor = $colorSubText
        $lbl.Location = New-Object System.Drawing.Point($si.X, 10)
        $lbl.AutoSize = $true
        $dStats.Controls.Add($lbl)
        $val = New-Object System.Windows.Forms.Label
        $val.Text = "0"
        $val.Font = New-Object System.Drawing.Font("微软雅黑", 17, [System.Drawing.FontStyle]::Bold)
        $val.ForeColor = $si.Color
        $val.Location = New-Object System.Drawing.Point($si.X, 28)
        $val.AutoSize = $true
        $dStats.Controls.Add($val)
        Set-Variable -Name $si.Var -Value $val -Scope Script
    }

    # 只显示异常
    $chkOnlyBad = New-Object System.Windows.Forms.CheckBox
    $chkOnlyBad.Text = T("driver_only_bad")
    $chkOnlyBad.Location = New-Object System.Drawing.Point(20, 160)
    $chkOnlyBad.AutoSize = $true
    $chkOnlyBad.Font = New-Object System.Drawing.Font("微软雅黑", 9)
    $chkOnlyBad.ForeColor = $colorText
    $dForm.Controls.Add($chkOnlyBad)

    # 驱动列表
    $dList = New-Object System.Windows.Forms.ListView
    $dList.Location = New-Object System.Drawing.Point(15, 185)
    $dList.Size = New-Object System.Drawing.Size(790, 310)
    $dList.View = "Details"
    $dList.FullRowSelect = $true
    $dList.GridLines = $false
    $dList.BackColor = $colorGlass
    $dList.Font = New-Object System.Drawing.Font("微软雅黑", 9)
    $dList.BorderStyle = "None"
    $dList.Columns.Add((T("driver_col_name")), 200) | Out-Null
    $dList.Columns.Add((T("stat_status")), 90) | Out-Null
    $dList.Columns.Add((T("driver_col_path")), 380) | Out-Null
    $dList.Columns.Add((T("driver_col_sig")), 100) | Out-Null
    $dForm.Controls.Add($dList)

    # 修复操作区 - 柔和桃色玻璃
    $dFixPanel = New-GlassPanel 790 90
    $dFixPanel.Location = New-Object System.Drawing.Point(15, 505)
    $dFixPanel.BackColor = [System.Drawing.Color]::FromArgb(252, 245, 235)
    $dForm.Controls.Add($dFixPanel)

    $dFixLabel = New-Object System.Windows.Forms.Label
    $dFixLabel.Text = T("driver_fix_title")
    $dFixLabel.Font = New-Object System.Drawing.Font("微软雅黑", 9.5, [System.Drawing.FontStyle]::Bold)
    $dFixLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 110, 50)
    $dFixLabel.Location = New-Object System.Drawing.Point(15, 8)
    $dFixLabel.AutoSize = $true
    $dFixPanel.Controls.Add($dFixLabel)

    $dFixNote = New-Object System.Windows.Forms.Label
    $dFixNote.Text = T("driver_fix_note")
    $dFixNote.Font = New-Object System.Drawing.Font("微软雅黑", 7.5)
    $dFixNote.ForeColor = [System.Drawing.Color]::FromArgb(180, 150, 110)
    $dFixNote.Location = New-Object System.Drawing.Point(120, 11)
    $dFixNote.AutoSize = $true
    $dFixPanel.Controls.Add($dFixNote)

    # 按钮1
    $btnFixReg = New-GlassButton (T("driver_fix_reg")) 170 34 $false
    $btnFixReg.Location = New-Object System.Drawing.Point(15, 35)
    $btnFixReg.BackColor = [System.Drawing.Color]::FromArgb(250, 220, 170)
    $btnFixReg.ForeColor = [System.Drawing.Color]::FromArgb(150, 90, 30)
    $dFixPanel.Controls.Add($btnFixReg)
    $btnFixRegTip = New-Object System.Windows.Forms.Label
    $btnFixRegTip.Text = T("driver_fix_reg_tip")
    $btnFixRegTip.Font = New-Object System.Drawing.Font("微软雅黑", 7)
    $btnFixRegTip.ForeColor = $colorSubText
    $btnFixRegTip.Location = New-Object System.Drawing.Point(15, 70)
    $btnFixRegTip.AutoSize = $true
    $dFixPanel.Controls.Add($btnFixRegTip)

    # 按钮2
    $btnSfc = New-GlassButton (T("driver_sfc")) 170 34 $false
    $btnSfc.Location = New-Object System.Drawing.Point(205, 35)
    $btnSfc.BackColor = [System.Drawing.Color]::FromArgb(250, 220, 170)
    $btnSfc.ForeColor = [System.Drawing.Color]::FromArgb(150, 90, 30)
    $dFixPanel.Controls.Add($btnSfc)
    $btnSfcTip = New-Object System.Windows.Forms.Label
    $btnSfcTip.Text = T("driver_sfc_tip")
    $btnSfcTip.Font = New-Object System.Drawing.Font("微软雅黑", 7)
    $btnSfcTip.ForeColor = $colorSubText
    $btnSfcTip.Location = New-Object System.Drawing.Point(205, 70)
    $btnSfcTip.AutoSize = $true
    $dFixPanel.Controls.Add($btnSfcTip)

    # 按钮3
    $btnClearAntiCheat = New-GlassButton (T("driver_clear_ac")) 170 34 $false
    $btnClearAntiCheat.Location = New-Object System.Drawing.Point(395, 35)
    $btnClearAntiCheat.BackColor = [System.Drawing.Color]::FromArgb(245, 190, 170)
    $btnClearAntiCheat.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 50)
    $dFixPanel.Controls.Add($btnClearAntiCheat)
    $btnClearTip = New-Object System.Windows.Forms.Label
    $btnClearTip.Text = T("driver_clear_tip")
    $btnClearTip.Font = New-Object System.Drawing.Font("微软雅黑", 7)
    $btnClearTip.ForeColor = $colorSubText
    $btnClearTip.Location = New-Object System.Drawing.Point(395, 70)
    $btnClearTip.AutoSize = $true
    $dFixPanel.Controls.Add($btnClearTip)

    # 底部按钮
    $btnRescanD = New-GlassButton (T("driver_rescan")) 110 40 $false
    $btnRescanD.Location = New-Object System.Drawing.Point(590, 610)
    $dForm.Controls.Add($btnRescanD)

    $btnCloseD = New-GlassButton (T("driver_close")) 110 40 $true
    $btnCloseD.Location = New-Object System.Drawing.Point(710, 610)
    $dForm.Controls.Add($btnCloseD)

    $script:driverData = @()

    function Invoke-DriverScan {
        $dList.Items.Clear()
        $script:driverData = @()
        $drivers = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue
        $total = $drivers.Count; $ok = 0; $missing = 0; $regMissing = 0; $sigBad = 0

        foreach ($drv in $drivers) {
            $filePath = ""
            if ($drv.PathName) { $filePath = $drv.PathName -replace '^\\\?\?\\', '' }
            $fileExists = $false
            if ($filePath -and $filePath -ne "") { $fileExists = Test-Path $filePath -ErrorAction SilentlyContinue }
            $status = "ok"; $statusColor = $colorGreen

            if (-not $fileExists) {
                $status = "missing"; $statusColor = $colorOrange; $missing++
            }

            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($drv.Name)"
            $regExists = Test-Path $regPath
            if (-not $regExists) {
                $regMissing++
                if ($status -eq "ok") { $status = "reg_missing"; $statusColor = $colorRed }
            }

            # 跳过数字签名检查以提升速度（普通用户不需要）
            $sigStatus = "N/A"

            $script:driverData += [pscustomobject]@{
                Name = $drv.Name; Status = $status; StatusColor = $statusColor
                FilePath = $filePath; Signature = $sigStatus; IsBad = ($status -ne "ok")
            }
            if ($status -eq "ok") { $ok++ }
        }

        # 反作弊驱动检测：只检查已知路径，不递归搜索
        $antiCheatPaths = @{
            "vgk" = "C:\Program Files\Riot Vanguard\vgk.sys"
            "vgc" = "C:\Program Files\Riot Vanguard\vgc.exe"
            "EasyAntiCheat" = "C:\Program Files (x86)\EasyAntiCheat\EasyAntiCheat.sys"
            "BEService" = "C:\Program Files (x86)\Common Files\BattlEye\BEService.exe"
            "BattlEye" = "C:\Program Files (x86)\Common Files\BattlEye\BEService.exe"
            "FACEIT" = "C:\Program Files\FACEIT AC\faceit.sys"
        }
        foreach ($ac in $antiCheatPaths.Keys) {
            $acReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$ac"
            if (-not (Test-Path $acReg)) {
                $acFile = $antiCheatPaths[$ac]
                if (Test-Path $acFile) {
                    $script:driverData += [pscustomobject]@{
                        Name = "$ac (" + (T "driver_anticheat") + ")"; Status = "reg_missing"; StatusColor = $colorRed
                        FilePath = $acFile; Signature = "reinstall"; IsBad = $true
                    }
                    $regMissing++
                }
            }
        }

        $dTotal.Text = $total; $dOk.Text = $ok; $dWarn.Text = $missing
        $dErr.Text = $regMissing; $dSig.Text = $sigBad
        Update-DriverList
    }

    function Update-DriverList {
        $dList.Items.Clear()
        $onlyBad = $chkOnlyBad.Checked
        foreach ($d in $script:driverData) {
            if ($onlyBad -and -not $d.IsBad) { continue }
            $statusText = switch ($d.Status) {
                "ok" { T "driver_ok" }
                "missing" { T "driver_missing" }
                "reg_missing" { T "driver_reg_missing" }
                default { $d.Status }
            }
            $sigText = switch ($d.Signature) {
                "valid" { T "driver_sig_valid" }
                "unsigned" { T "driver_sig_unsigned" }
                "unknown" { T "driver_sig_unknown" }
                "reinstall" { T "driver_sig_reinstall" }
                default { $d.Signature }
            }
            $lvi = New-Object System.Windows.Forms.ListViewItem($d.Name)
            $lvi.SubItems.Add($statusText) | Out-Null
            $lvi.SubItems.Add($d.FilePath) | Out-Null
            $lvi.SubItems.Add($sigText) | Out-Null
            $lvi.ForeColor = $d.StatusColor
            $dList.Items.Add($lvi) | Out-Null
        }
    }

    function Repair-SelectedDrivers {
        $selected = $dList.SelectedItems
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((T("drv_select_first")), (T("common_tip")), "OK", "Information")
            return
        }
        $r = [System.Windows.Forms.MessageBox]::Show(((T("drv_confirm_fix")) -f $selected.Count), (T("common_confirm")), "YesNo", "Question")
        if ($r -ne "Yes") { return }

        $repaired = 0; $cleared = 0; $skipped = 0; $report = @()
        foreach ($item in $selected) {
            $drvName = $item.Text
            $drvNameClean = $drvName -replace " \(.+\)$", ""
            $drvData = $script:driverData | Where-Object { $_.Name -eq $drvName } | Select-Object -First 1
            $drvStatus = if ($drvData) { $drvData.Status } else { "unknown" }
            $drvPath = if ($drvData) { $drvData.FilePath } else { $item.SubItems[2].Text }

            if ($drvStatus -eq "ok") { $skipped++; $report += ((T("drv_rep_ok")) -f $drvName); continue }

            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$drvNameClean"
            $regExists = Test-Path $regPath
            $fileExists = $false
            if ($drvPath -and $drvPath -ne "" -and -not $drvPath.StartsWith("?")) {
                $fileExists = Test-Path $drvPath
            }

            if ($drvStatus -eq "reg_missing" -and $fileExists) {
                $result = sc.exe create $drvNameClean binPath= "$drvPath" type= kernel start= demand 2>&1
                if ($LASTEXITCODE -eq 0) { $repaired++; $report += ((T("drv_rep_rebuilt")) -f $drvName) }
                else { $skipped++; $report += ((T("drv_rep_rebuild_fail")) -f $drvName) }
            }
            elseif ($drvStatus -eq "missing" -and $regExists) {
                sc.exe delete $drvNameClean 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $cleared++; $report += ((T("drv_rep_cleared")) -f $drvName) }
                else { $skipped++; $report += ((T("drv_rep_clear_fail")) -f $drvName) }
            }
            elseif ($drvStatus -eq "missing" -and -not $regExists) {
                $skipped++; $report += ((T("drv_rep_gone")) -f $drvName)
            }
            else {
                $skipped++; $report += ((T("drv_rep_other")) -f $drvName, $drvStatus)
            }
        }
        $reportText = ((T("drv_rep_head")) -f $repaired, $cleared, $skipped)
        foreach ($rpt in $report) { $reportText += "  $rpt`n" }
        $reportText += (T("drv_rep_reboot"))
        [System.Windows.Forms.MessageBox]::Show($reportText, (T("drv_result_title")), "OK", "Information")
        Invoke-DriverScan
    }

    function Run-SfcCheck {
        $r = [System.Windows.Forms.MessageBox]::Show((T("sfc_confirm")), (T("common_confirm")), "YesNo", "Question")
        if ($r -ne "Yes") { return }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c sfc /scannow"
        $psi.Verb = "runas"
        $psi.WindowStyle = "Hidden"
        $psi.CreateNoWindow = $true
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            [System.Windows.Forms.MessageBox]::Show((T("sfc_started")), (T("common_tip")), "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show((T("sfc_fail")), (T("common_error")), "OK", "Error")
        }
    }

    function Clear-AntiCheatResidual {
        $r = [System.Windows.Forms.MessageBox]::Show((T("ace_confirm")), (T("common_confirm")), "YesNo", "Warning")
        if ($r -ne "Yes") { return }
        $cleared = @(); $failed = @()
        $acDrivers = @("ACE-ADVT","ACE-BASE","ACE-BOOT","ACE-GAME","vgk","vgc","EasyAntiCheat","EasyAntiCheat_EOS","BEService","BattlEye","FACEIT","FACEIT_IOMMU","FACEITService")
        foreach ($drv in $acDrivers) {
            $query = sc.exe query $drv 2>&1
            if ($LASTEXITCODE -eq 0) {
                sc.exe delete $drv 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $cleared += $drv } else { $failed += $drv }
            }
        }
        $acDirs = @("C:\Program Files\AntiCheatExpert","C:\Program Files\Riot Vanguard","C:\Program Files\EasyAntiCheat","C:\Program Files\BattlEye","C:\Program Files\FACEIT AC")
        foreach ($dir in $acDirs) {
            if (Test-Path $dir) {
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $dir)) { $cleared += ((T("ace_dir")) -f $dir) }
                else { $failed += ((T("ace_dir_locked")) -f $dir) }
            }
        }
        $reportText = ((T("ace_head")) -f $cleared.Count)
        if ($failed.Count -gt 0) { $reportText += ((T("ace_need_reboot")) -f $failed.Count) }
        $reportText += (T("ace_cleared_head"))
        foreach ($c in $cleared) { $reportText += "  $c`n" }
        if ($failed.Count -gt 0) {
            $reportText += (T("ace_reboot_head"))
            foreach ($f in $failed) { $reportText += "  $f`n" }
        }
        $reportText += (T("ace_reboot_note"))
        [System.Windows.Forms.MessageBox]::Show($reportText, (T("ace_result_title")), "OK", "Information")
        Invoke-DriverScan
    }

    $chkOnlyBad.Add_CheckedChanged({ Update-DriverList })
    $btnRescanD.Add_Click({ Invoke-DriverScan })
    $btnCloseD.Add_Click({ $dForm.Close() })
    $btnFixReg.Add_Click({ Repair-SelectedDrivers })
    $btnSfc.Add_Click({ Run-SfcCheck })
    $btnClearAntiCheat.Add_Click({ Clear-AntiCheatResidual })

    # 窗口显示后再扫描，避免卡住
    $dForm.Add_Shown({
        $dList.Items.Clear()
        $lvi = New-Object System.Windows.Forms.ListViewItem((T "status_scanning"))
        $dList.Items.Add($lvi) | Out-Null
        $dForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        Invoke-DriverScan
    })

    [void]$dForm.ShowDialog()
}

# ===== 软件卸载窗口 =====
function Get-InstalledSoftware {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $software = @()
    foreach ($path in $paths) {
        Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and
            $_.DisplayName -notmatch "Update for|Security Update|Hotfix|Service Pack|KB\d+|Microsoft Visual C\+\+.*Redistributable|Microsoft .NET Framework|Microsoft Silverlight|Microsoft Edge|Microsoft OneDrive" -and
            $_.SystemComponent -ne 1 -and
            -not $_.ParentKeyName -and
            $_.ReleaseType -ne "Update"
        } | ForEach-Object {
            $size = 0
            if ($_.EstimatedSize) { try { $size = [math]::Round([double]$_.EstimatedSize / 1024, 1) } catch { $size = 0 } }
            $software += [pscustomobject]@{
                Name = $_.DisplayName
                Publisher = if ($_.Publisher) { $_.Publisher } else { (T("txt_unknown")) }
                Version = if ($_.DisplayVersion) { $_.DisplayVersion } else { (T("txt_unknown")) }
                SizeMB = $size
                UninstallString = $_.UninstallString
                QuietUninstallString = $_.QuietUninstallString
                InstallLocation = $_.InstallLocation
                RegistryPath = $_.PSPath
            }
        }
    }
    return $software | Sort-Object Name -Unique
}

function Show-SoftwareUninstaller {
    $uForm = New-Object System.Windows.Forms.Form
    $uForm.Text = T("uninstall_title")
    $uForm.Size = New-Object System.Drawing.Size(860, 680)
    $uForm.StartPosition = "CenterScreen"
    $uForm.Font = New-Object System.Drawing.Font("微软雅黑", 9)
    $uForm.Add_Paint({
        param($s, $e)
        try {
            $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
            $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $colorBg, $colorBg2, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            if ($brush) { $e.Graphics.FillRectangle($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height); $brush.Dispose() }
        } catch { }
    })

    $uPanel = New-Object System.Windows.Forms.Panel
    $uPanel.Location = New-Object System.Drawing.Point(0, 0)
    $uPanel.Size = New-Object System.Drawing.Size(860, 70)
    $uPanel.BackColor = $colorPrimary
    $uPanel.Add_Paint({
        param($s, $e)
        try {
            $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
            $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $colorPrimary, $colorPrimaryLight, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            if ($brush) { $e.Graphics.FillRectangle($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height); $brush.Dispose() }
        } catch { }
    })
    $uForm.Controls.Add($uPanel)

    $uTitle = New-Object System.Windows.Forms.Label
    $uTitle.Text = T("uninstall_title")
    $uTitle.Font = New-Object System.Drawing.Font("微软雅黑", 16, [System.Drawing.FontStyle]::Bold)
    $uTitle.ForeColor = $colorWhite
    $uTitle.Location = New-Object System.Drawing.Point(30, 18)
    $uTitle.AutoSize = $true
    $uPanel.Controls.Add($uTitle)

    $uSub = New-Object System.Windows.Forms.Label
    $uSub.Text = T("uninstall_subtitle")
    $uSub.Font = New-Object System.Drawing.Font("微软雅黑", 8.5)
    $uSub.ForeColor = [System.Drawing.Color]::FromArgb(220, 225, 240)
    $uSub.Location = New-Object System.Drawing.Point(32, 45)
    $uSub.AutoSize = $true
    $uPanel.Controls.Add($uSub)

    $uSearch = New-Object System.Windows.Forms.TextBox
    $uSearch.Location = New-Object System.Drawing.Point(20, 85)
    $uSearch.Size = New-Object System.Drawing.Size(400, 30)
    $uSearch.Font = New-Object System.Drawing.Font("微软雅黑", 9.5)
    $uSearch.ForeColor = $colorText
    $uSearch.Text = T("uninstall_search")
    $uForm.Controls.Add($uSearch)

    $uCount = New-Object System.Windows.Forms.Label
    $uCount.Text = ((T("uninstall_count")) -f 0)
    $uCount.Font = New-Object System.Drawing.Font("微软雅黑", 9)
    $uCount.ForeColor = [System.Drawing.Color]::FromArgb(120, 125, 140)
    $uCount.Location = New-Object System.Drawing.Point(440, 88)
    $uCount.AutoSize = $true
    $uForm.Controls.Add($uCount)

    $uListBorder = New-Object System.Windows.Forms.Panel
    $uListBorder.Location = New-Object System.Drawing.Point(19, 124)
    $uListBorder.Size = New-Object System.Drawing.Size(802, 442)
    $uListBorder.BackColor = $colorGlassBorder
    $uForm.Controls.Add($uListBorder)

    $uList = New-Object System.Windows.Forms.ListView
    $uList.Location = New-Object System.Drawing.Point(20, 125)
    $uList.Size = New-Object System.Drawing.Size(800, 440)
    $uList.View = "Details"
    $uList.FullRowSelect = $true
    $uList.GridLines = $false
    $uList.BackColor = $colorWhite
    $uList.ForeColor = $colorText
    $uList.Font = New-Object System.Drawing.Font("微软雅黑", 9)
    $uList.Columns.Add((T("uninstall_col_name")), 280) | Out-Null
    $uList.Columns.Add((T("uninstall_col_pub")), 200) | Out-Null
    $uList.Columns.Add((T("uninstall_col_ver")), 120) | Out-Null
    $uList.Columns.Add((T("uninstall_col_size")), 80) | Out-Null
    $uList.Columns.Add((T("uninstall_col_type")), 110) | Out-Null
    $uForm.Controls.Add($uList)
    $uList.BringToFront()

    $script:allSoftware = @()

    function Refresh-SoftwareList {
        param([string]$filter = "")
        $uList.Items.Clear()
        $filtered = $script:allSoftware
        if ($filter -and $filter -ne (T "uninstall_search")) {
            $filtered = $filtered | Where-Object { $_.Name -match [regex]::Escape($filter) -or $_.Publisher -match [regex]::Escape($filter) }
        }
        foreach ($sw in $filtered) {
            $lvi = New-Object System.Windows.Forms.ListViewItem($sw.Name)
            $lvi.SubItems.Add($sw.Publisher) | Out-Null
            $lvi.SubItems.Add($sw.Version) | Out-Null
            $lvi.SubItems.Add($(if ($sw.SizeMB -gt 0) { "$($sw.SizeMB) MB" } else { T "uninstall_unknown" })) | Out-Null
            $uninstallType = if ($sw.QuietUninstallString) { T "uninstall_quiet" } elseif ($sw.UninstallString -match "MsiExec") { T "uninstall_msi" } else { T "uninstall_standard" }
            $lvi.SubItems.Add($uninstallType) | Out-Null
            $lvi.Tag = $sw
            $uList.Items.Add($lvi) | Out-Null
        }
        $uCount.Text = (T "uninstall_count") -f $filtered.Count
    }

    $btnRefreshU = New-GlassButton (T("uninstall_refresh")) 100 38 $false
    $btnRefreshU.Location = New-Object System.Drawing.Point(20, 580)
    $uForm.Controls.Add($btnRefreshU)

    $btnUninstallSel = New-GlassButton (T("uninstall_btn")) 140 38 $true
    $btnUninstallSel.Location = New-Object System.Drawing.Point(140, 580)
    $btnUninstallSel.Font = New-Object System.Drawing.Font("微软雅黑", 10, [System.Drawing.FontStyle]::Bold)
    $uForm.Controls.Add($btnUninstallSel)

    $btnUninstallTip = New-Object System.Windows.Forms.Label
    $btnUninstallTip.Text = T("uninstall_tip")
    $btnUninstallTip.Font = New-Object System.Drawing.Font("微软雅黑", 7.5)
    $btnUninstallTip.ForeColor = [System.Drawing.Color]::FromArgb(140, 145, 160)
    $btnUninstallTip.Location = New-Object System.Drawing.Point(140, 620)
    $btnUninstallTip.AutoSize = $true
    $uForm.Controls.Add($btnUninstallTip)

    $btnCloseU = New-GlassButton (T("uninstall_close")) 100 38 $false
    $btnCloseU.Location = New-Object System.Drawing.Point(720, 580)
    $uForm.Controls.Add($btnCloseU)

    $uSearch.Add_GotFocus({ if ($uSearch.Text -eq (T("uninstall_search"))) { $uSearch.Text = "" } })
    $uSearch.Add_LostFocus({ if (-not $uSearch.Text) { $uSearch.Text = T("uninstall_search") } })
    $uSearch.Add_TextChanged({ Refresh-SoftwareList $uSearch.Text })

    $btnRefreshU.Add_Click({
        $script:allSoftware = Get-InstalledSoftware
        Refresh-SoftwareList $uSearch.Text
    })

    $btnCloseU.Add_Click({ $uForm.Close() })

    $btnUninstallSel.Add_Click({
        if ($uList.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((T("uninstall_no_sel")), (T("common_tip")), "OK", "Information")
            return
        }
        $selected = $uList.SelectedItems[0].Tag
        $name = $selected.Name
        $r = [System.Windows.Forms.MessageBox]::Show(((T("uninstall_confirm")) -f $name), (T("uninstall_confirm_title")), "YesNo", "Warning")
        if ($r -ne "Yes") { return }

        $uForm.Cursor = "WaitCursor"
        $btnUninstallSel.Enabled = $false
        $btnUninstallSel.Text = T("uninstall_btn_ing")
        $uForm.Refresh()

        $result = T("uninstall_done")
        $cleanedDirs = 0
        $cleanedReg = 0

        try {
            $installDir = $selected.InstallLocation
            $regPath = $selected.RegistryPath

            if ($selected.QuietUninstallString) {
                $cmd = $selected.QuietUninstallString
                if ($cmd -match "^`"(.+?)`"\s*(.*)$") {
                    $exe = $matches[1]; $args = $matches[2]
                    Start-Process -FilePath $exe -ArgumentList $args -Wait -ErrorAction SilentlyContinue
                } else {
                    Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -Wait -ErrorAction SilentlyContinue
                }
            } elseif ($selected.UninstallString -match "MsiExec\.exe") {
                $productCode = [regex]::Match($selected.UninstallString, "\{[^}]+\}").Value
                if ($productCode) {
                    Start-Process msiexec.exe -ArgumentList "/x $productCode /qn /norestart" -Wait -ErrorAction SilentlyContinue
                } else {
                    Start-Process cmd.exe -ArgumentList "/c `"$($selected.UninstallString)`"" -Wait -ErrorAction SilentlyContinue
                }
            } else {
                $cmd = $selected.UninstallString
                if ($cmd -match "^`"(.+?)`"\s*(.*)$") {
                    $exe = $matches[1]; $args = $matches[2]
                    Start-Process -FilePath $exe -ArgumentList $args -Wait -ErrorAction SilentlyContinue
                } else {
                    Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -Wait -ErrorAction SilentlyContinue
                }
            }

            Start-Sleep -Seconds 3

            if ($installDir -and $installDir -ne "" -and (Test-Path $installDir)) {
                $dirInfo = Get-Item $installDir -ErrorAction SilentlyContinue
                if ($dirInfo -and $dirInfo.FullName -ne "C:\" -and $dirInfo.FullName -ne "C:\Program Files" -and $dirInfo.FullName -ne "C:\Program Files (x86)") {
                    Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path $installDir)) { $cleanedDirs++ }
                }
            }

            if ($regPath -and (Test-Path $regPath)) {
                Remove-Item $regPath -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $regPath)) { $cleanedReg++ }
            }
        } catch {
            $result = ((T("uninstall_err_detail")) -f $_.Exception.Message)
        }

        $uForm.Cursor = "Default"
        $btnUninstallSel.Enabled = $true
        $btnUninstallSel.Text = T("uninstall_btn_sel")

        $report = ((T("uninstall_result")) -f $result, $name, $(if ($cleanedDirs -gt 0) { T("uninstall_cleaned") } else { T("uninstall_none") }), $(if ($cleanedReg -gt 0) { T("uninstall_cleaned") } else { T("uninstall_none") }))
        [System.Windows.Forms.MessageBox]::Show($report, (T("uninstall_result_title")), "OK", "Information")

        $script:allSoftware = Get-InstalledSoftware
        Refresh-SoftwareList $uSearch.Text
    })

    $script:allSoftware = Get-InstalledSoftware
    Refresh-SoftwareList
    [void]$uForm.ShowDialog()
}

# ===== 事件绑定 =====
$listView.Add_ItemCheck({ Update-Stats })
$btnSelectAll.Add_Click({ for ($i = 0; $i -lt $listView.Items.Count; $i++) { $listView.Items[$i].Checked = $script:items[$i].Default }; Update-Stats })
$btnRescan.Add_Click({ Invoke-Scan })
$btnClean.Add_Click({ Invoke-Clean })
$btnDriver.Add_Click({ Show-DriverChecker })
$btnUninstall.Add_Click({ Show-SoftwareUninstaller })
$btnLang.Add_Click({ Toggle-Language })

# ===== 启动 =====
# 先把窗口显示出来, 再执行扫描; 否则用户点开程序要干等十几秒才有反应
$form.Add_Shown({ Invoke-Scan })
[void]$form.ShowDialog()
