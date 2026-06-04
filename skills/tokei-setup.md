# Tokei Setup — 一键配置多设备用量同步

交互式引导用户完成 Tokei 多设备同步的全部配置。

## 触发

用户说 "setup tokei"、"配置 tokei 同步"、"tokei sync setup"、"设置用量同步" 时触发。

## 执行流程

按以下步骤逐一检查和执行,已完成的步骤跳过:

### 步骤 1: 检查环境

```bash
# 检查必要工具
which gh >/dev/null 2>&1 && echo "✅ gh CLI" || echo "❌ gh CLI (brew install gh)"
which git >/dev/null 2>&1 && echo "✅ git" || echo "❌ git"
which python3 >/dev/null 2>&1 && echo "✅ python3" || echo "❌ python3"
[ -f ~/.tokei/config.json ] && echo "✅ Tokei 已配置" || echo "⏳ Tokei 未配置"
```

如果缺少 `gh`,提示安装后继续。

### 步骤 2: 创建 GitHub 同步仓库

检查是否已有同步仓库:

```bash
if [ -f ~/.tokei/config.json ]; then
    SYNC_DIR=$(python3 -c "import json;print(json.load(open('$HOME/.tokei/config.json')).get('sync_dir',''))" 2>/dev/null)
    if [ -n "$SYNC_DIR" ] && [ -d "$(eval echo $SYNC_DIR)" ]; then
        echo "✅ 同步仓库已存在: $SYNC_DIR"
        # 跳到步骤 4
    fi
fi
```

如果不存在,创建:

```bash
# 创建私有仓库
gh repo create tokei-sync --private --clone
cd tokei-sync

# 放入采集脚本和价格文件
cp /path/to/usage.30s.py .
cp /path/to/pricing.json . 2>/dev/null
cp /path/to/pricing_overrides.json . 2>/dev/null
cp /path/to/install.sh .

# 初始提交
git add -A && git commit -m "init: tokei sync repo" && git push
```

**注意**: `/path/to/` 应替换为实际的 Tokei 项目路径。可以通过以下方式找到:
```bash
# 常见位置
ls ~/code/claude-code-research/tools/usage-bar/usage.30s.py 2>/dev/null || \
ls ~/tokei/usage.30s.py 2>/dev/null || \
echo "请告诉我 usage.30s.py 的路径"
```

### 步骤 3: 配置本机

```bash
mkdir -p ~/.tokei
DEVICE_NAME=$(hostname -s)
SYNC_DIR="$HOME/tokei-sync"  # 步骤 2 克隆的路径

cat > ~/.tokei/config.json <<EOF
{
  "sync_dir": "$SYNC_DIR",
  "device_id": "$DEVICE_NAME"
}
EOF

echo "✅ 本机配置完成: $DEVICE_NAME → $SYNC_DIR"
```

### 步骤 4: 显示远程部署命令

读取实际的 git remote URL:

```bash
REPO_URL=$(git -C "$SYNC_DIR" remote get-url origin 2>/dev/null)
echo ""
echo "═══ 远程服务器部署(复制到远程终端执行) ═══"
echo ""
echo "  git clone $REPO_URL ~/.tokei/sync && \\"
echo "  echo '{\"sync_dir\":\"~/.tokei/sync\",\"device_id\":\"'\\$(hostname -s)'\"}' > ~/.tokei/config.json && \\"
echo "  echo '*/5 * * * * cd ~/.tokei/sync && python3 usage.30s.py --json >/dev/null && git pull -q && git add -A && git diff --cached --quiet || git commit -qm sync && git push -q' | crontab - && \\"
echo "  echo '✅ 部署完成'"
echo ""
```

### 步骤 5: 可选 — 通过 SSH 直接部署

如果用户提供了远程服务器地址:

```bash
# 用户提供: ssh user@server
REMOTE="user@server"
ssh "$REMOTE" "git clone $REPO_URL ~/.tokei/sync && echo '{\"sync_dir\":\"~/.tokei/sync\",\"device_id\":\"'\$(hostname -s)'\"}' > ~/.tokei/config.json && (crontab -l 2>/dev/null; echo '*/5 * * * * cd ~/.tokei/sync && python3 usage.30s.py --json >/dev/null && git pull -q && git add -A && git diff --cached --quiet || git commit -qm sync && git push -q') | crontab -"
```

### 步骤 6: 验证

```bash
# 本机立即同步一次
cd "$SYNC_DIR" && python3 usage.30s.py --json >/dev/null 2>&1
git add -A && git diff --cached --quiet || git commit -qm "sync $(hostname -s)" && git push -q

echo ""
echo "═══ 完成 ═══"
echo "  ✅ 本机: $(cat ~/.tokei/config.json | python3 -c 'import sys,json;print(json.load(sys.stdin)["device_id"])')"
ls "$SYNC_DIR"/*.json 2>/dev/null | while read f; do
    name=$(basename "$f" .json)
    ts=$(python3 -c "import json;print(json.load(open('$f')).get('_ts','?'))" 2>/dev/null)
    echo "  📱 $name (最后同步: $(date -r $ts '+%m-%d %H:%M' 2>/dev/null || echo '?'))"
done
echo ""
echo "  Tokei 菜单栏 → 设置 → 多设备同步 → 开启 → 选择目录: $SYNC_DIR"
```

## 交互策略

- 每一步执行前先告诉用户要做什么,得到确认后再执行
- 已完成的步骤直接跳过并显示 ✅
- 出错时给出具体的修复建议
- 最后给出清晰的总结: 哪些设备已连接、下一步做什么

## 回答风格

简洁直接,每步一行结果。不要长段解释。像 CLI 安装向导一样。
