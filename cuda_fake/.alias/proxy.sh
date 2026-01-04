# ===========================================
# Proxy Functions
# ===========================================
proxy_en() {
    export https_proxy="http://222.29.97.81:1080"
    export http_proxy="http://222.29.97.81:1080"
    git config --global http.proxy "http://222.29.97.81:1080"
    git config --global https.proxy "http://222.29.97.81:1080"
}

proxy_dis() {
    unset https_proxy
    unset http_proxy
    git config --global --unset http.proxy
    git config --global --unset https.proxy
}

