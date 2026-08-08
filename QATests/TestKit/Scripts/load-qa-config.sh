#!/bin/bash

# Loads maintainer-local QA policy without evaluating it as shell code.
# The caller must set ROOT to the repository root before invoking this function.
load_battery_monitor_qa_config() {
    local config expected_root team_id sign_identity

    config=${BATTERYMONITOR_QA_CONFIG:-"$ROOT/QATests/Personal/Config/QAConfig.local.plist"}
    if [[ "$config" != /* ]]; then
        config="$ROOT/$config"
    fi
    if [ ! -f "$config" ]; then
        echo "缺少本机 QA 配置：$config" >&2
        echo "请复制 QATests/TestKit/Config/QAConfig.example.plist 到 QATests/Personal/Config/QAConfig.local.plist，并填写本机路径和开发签名。" >&2
        return 1
    fi

    if ! expected_root=$(/usr/bin/plutil -extract ExpectedProjectRoot raw "$config" 2>/dev/null); then
        echo "QA 配置缺少 ExpectedProjectRoot：$config" >&2
        return 1
    fi
    if ! team_id=$(/usr/bin/plutil -extract TeamID raw "$config" 2>/dev/null); then
        echo "QA 配置缺少 TeamID：$config" >&2
        return 1
    fi
    if ! sign_identity=$(/usr/bin/plutil -extract SignIdentity raw "$config" 2>/dev/null); then
        echo "QA 配置缺少 SignIdentity：$config" >&2
        return 1
    fi

    if [ "$ROOT" != "$expected_root" ]; then
        echo "项目路径不匹配：当前 $ROOT；QA 配置要求 $expected_root" >&2
        return 1
    fi
    if [ -z "$team_id" ] || [ -z "$sign_identity" ]; then
        echo "QA 配置中的 TeamID 或 SignIdentity 为空：$config" >&2
        return 1
    fi

    QA_CONFIG_PATH="$config"
    QA_TEAM_ID="$team_id"
    QA_SIGN_IDENTITY="$sign_identity"
}
