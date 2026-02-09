#!/bin/bash
# OpenClaw Logs Viewer
# Muestra logs en tiempo real

echo "═══════════════════════════════════════"
echo "   OpenClaw Logs (Ctrl+C para salir)"
echo "═══════════════════════════════════════"
echo ""

tail -f ~/.openclaw/logs/node.log /tmp/openclaw-tunnel.log 2>/dev/null
