#!/usr/bin/env bash
pkill -f cloud-sql-proxy 2>/dev/null || true
pkill -f "streamlit run dashboard/app.py" 2>/dev/null || true
echo "AMPEX gestoppt"
