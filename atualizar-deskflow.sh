#!/bin/bash
# =============================================================================
# atualizar-deskflow — atualiza o DeskFlow (backend + frontend) dentro do
# container deskflow-2610, sem esperar uma nova imagem no Docker Hub.
#
# O frontend vem embutido no binário deskflow_srv (o nginx do container só
# repassa para ele), então trocar o binário atualiza as duas partes.
#
# Uso (no host do Docker):
#   docker exec -it deskflow-2610 atualizar-deskflow            # versão mais recente
#   docker exec -it deskflow-2610 atualizar-deskflow --verificar # só mostra as versões
#   docker exec -it deskflow-2610 atualizar-deskflow --restaurar # volta o binário anterior
#   docker exec -it deskflow-2610 atualizar-deskflow --arquivo /opt/deskflow/deploy-X.zip
#                                                     # sem internet: zip baixado à parte
# Imagem antiga, sem o comando:
#   docker exec -i deskflow-2610 bash -s -- --sim < atualizar-deskflow.sh
#
# Opções: --sim (não pergunta), --forcar (reinstala mesmo versão igual/menor).
#
# Automático: o entrypoint roda `atualizar-deskflow --auto` a cada subida do
# container (antes do backend), salvo DESKFLOW_AUTO_UPDATE=0 no compose. --auto
# não pergunta, não reinicia (o entrypoint inicia o backend logo depois) e não
# age depois de um --restaurar (versão fixada até a próxima atualização manual).
# Consulta o site no máximo uma vez a cada 24 h (DESKFLOW_AUTO_UPDATE_HORAS),
# por mais que o container reinicie: a última consulta bem-sucedida fica em
# /opt/deskflow/.deskflow_auto_check. Falha (sem internet etc.) não conta e
# tenta de novo na próxima subida; imagem nova também volta a consultar.
#
# Fluxo: manifesto https://deskflow.com.br/updates/latest.json → download do
# zip → confere o SHA-256 → extrai deskflow_srv → backup do atual → troca
# atômica → reinicia o container. O entrypoint mantém o binário trocado
# enquanto a imagem não mudar (marcador /opt/deskflow/.deskflow_manual);
# um `docker compose pull` + `up -d` com imagem nova volta a valer a da imagem.
# =============================================================================
set -euo pipefail

MANIFEST_URL="https://deskflow.com.br/updates/latest.json"
DIR="${DESKFLOW_DIR:-/opt/deskflow}"
BIN="$DIR/deskflow_srv"
IMG_BIN="${DESKFLOW_IMG_BIN:-/usr/share/deskflow/deskflow_srv}"
MARKER="$DIR/.deskflow_manual"
CHECK="$DIR/.deskflow_auto_check"
INTERVALO_H="${DESKFLOW_AUTO_UPDATE_HORAS:-24}"
ENTRYPOINT="${DESKFLOW_ENTRYPOINT:-/usr/local/bin/deskflow-entrypoint.sh}"
BKP_PREFIX="deskflow_srv.bkp-atualizacao-"
KEEP_BKP=3

ARQUIVO=""; SIM=0; FORCAR=0; MODO=atualizar; AUTO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --arquivo) ARQUIVO="${2:?--arquivo precisa do caminho do zip}"; shift 2 ;;
        --sim|-y) SIM=1; shift ;;
        --auto) AUTO=1; SIM=1; shift ;;
        --forcar) FORCAR=1; shift ;;
        --verificar) MODO=verificar; shift ;;
        --restaurar) MODO=restaurar; shift ;;
        -h|--help) sed -n '2,33p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "Opção desconhecida: $1 (use --help)" >&2; exit 2 ;;
    esac
done

die() { echo "ERRO: $*" >&2; exit 1; }
info() { echo "== $*"; }

[ -f "$IMG_BIN" ] && [ -d "$DIR" ] || die "rode dentro do container do DeskFlow: docker exec -it deskflow-2610 atualizar-deskflow"
command -v python3 >/dev/null || die "python3 não encontrado no container"

confirmar() {
    [ "$SIM" = 1 ] && return 0
    [ -t 0 ] || die "sem terminal para confirmar — use 'docker exec -it' ou --sim"
    read -r -p "$1 [s/N] " r
    case "$r" in s|S|sim|SIM) return 0 ;; *) echo "Cancelado."; exit 0 ;; esac
}

versao_atual() {
    local v
    v="$(curl -s -m 5 http://127.0.0.1:8074/version 2>/dev/null \
        | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("version") or "")
except Exception: print("")' 2>/dev/null || true)"
    # Backend parado (caso do --auto, que roda antes dele): versão gravada na
    # última atualização. Sem marcador = binário da imagem, versão desconhecida.
    if [ -z "$v" ] && [ -f "$MARKER" ]; then
        v="$(sed -n 's/^version=\([0-9][0-9.]*\)$/\1/p' "$MARKER")"
    fi
    # Sem marcador e binário igual ao da imagem: versão gravada na imagem.
    if [ -z "$v" ] && [ ! -f "$MARKER" ] && [ -f "${IMG_BIN%/*}/VERSION" ] \
        && [ "$(sha256sum < "$BIN")" = "$(sha256sum < "$IMG_BIN")" ]; then
        v="$(tr -d '[:space:]' < "${IMG_BIN%/*}/VERSION")"
    fi
    printf '%s' "$v"
}

# Versão a > b (ordem de versão, não de texto: 3.0.100 > 3.0.99).
maior() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }

# Reinicia o próprio container. Com política always/unless-stopped (a do
# compose) basta encerrar o processo principal: o Docker sobe o container de
# novo e o entrypoint mantém o binário trocado. Um `docker restart` disparado
# daqui de dentro morreria junto com o container no meio da operação.
reiniciar() {
    local alvo pol pid
    alvo="$(hostname)"
    dk() { timeout 20 docker "$@"; }
    dk inspect "$alvo" >/dev/null 2>&1 || alvo=deskflow-2610
    if ! dk inspect "$alvo" >/dev/null 2>&1; then
        echo "Não consegui identificar o container. Rode no host: docker restart deskflow-2610"
        return 0
    fi
    pol="$(dk inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$alvo" || true)"
    pid="$(dk inspect -f '{{.State.Pid}}' "$alvo" || true)"
    case "$pol" in
        always|unless-stopped)
            # pid: host → o PID do host é o visível aqui; nunca sinalizar 0/1.
            if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && kill -0 "$pid" 2>/dev/null; then
                info "Reiniciando o DeskFlow. A interface volta em ~15 s na porta 8073."
                kill -TERM "$pid"
                return 0
            fi ;;
    esac
    echo "Binário trocado, mas o container precisa ser reiniciado. Rode no host: docker restart $alvo"
}

# Entrypoint antigo (imagens 1.0.0) copia o binário da imagem a cada subida e
# desfaria a atualização no restart: nesse caso a cópia da imagem dentro do
# container também é trocada (vale até o container ser recriado).
entrypoint_antigo() { ! grep -q '.deskflow_manual' "$ENTRYPOINT" 2>/dev/null; }

instalar_binario() {   # $1 = binário novo já validado, $2 = versão, $3 = 1 fixa a versão
    local novo="$1" ver="$2" pin="${3:-0}" img_sha
    img_sha="$(sha256sum "$IMG_BIN" | cut -d' ' -f1)"

    if [ -f "$BIN" ]; then
        local bkp="$DIR/${BKP_PREFIX}$(date +%Y%m%d-%H%M%S)"
        cp -p "$BIN" "$bkp"
        info "Backup do binário atual: $bkp"
        # Só os backups deste script; os demais arquivos da pasta não são tocados.
        ls -1t "$DIR"/${BKP_PREFIX}* 2>/dev/null | tail -n +$((KEEP_BKP + 1)) | xargs -r rm -f
    fi

    cp "$novo" "$BIN.new"
    chmod 755 "$BIN.new"
    mv -f "$BIN.new" "$BIN"

    if entrypoint_antigo; then
        cp "$novo" "$IMG_BIN.new" && chmod 755 "$IMG_BIN.new" && mv -f "$IMG_BIN.new" "$IMG_BIN"
        img_sha="$(sha256sum "$IMG_BIN" | cut -d' ' -f1)"
        echo "   (imagem antiga: binário de /usr/share/deskflow também trocado; vale até recriar o container)"
    fi

    printf 'version=%s\nimage_sha=%s\ndate=%s\npin=%s\n' "$ver" "$img_sha" "$(date '+%Y-%m-%d %H:%M:%S')" "$pin" > "$MARKER"
}

if [ "$AUTO" = 1 ] && grep -qx 'pin=1' "$MARKER" 2>/dev/null; then
    info "Atualização automática ignorada: versão restaurada com --restaurar (rode atualizar-deskflow para voltar a atualizar)"
    exit 0
fi

# --auto: uma consulta ao site por intervalo, valendo só para a mesma imagem.
img_sha_atual() { sha256sum "$IMG_BIN" 2>/dev/null | cut -d' ' -f1; }
marcar_verificacao() {
    printf 'ts=%s\nimage_sha=%s\n' "$(date +%s)" "$(img_sha_atual)" > "$CHECK" 2>/dev/null || true
}
if [ "$AUTO" = 1 ] && [ "$FORCAR" = 0 ] && [ -f "$CHECK" ] && grep -qx "image_sha=$(img_sha_atual)" "$CHECK"; then
    ult="$(sed -n 's/^ts=\([0-9][0-9]*\)$/\1/p' "$CHECK")"
    agora="$(date +%s)"
    if [ -n "$ult" ] && [ "$ult" -le "$agora" ] && [ $((agora - ult)) -lt $((INTERVALO_H * 3600)) ]; then
        info "Atualização automática: site já consultado há $(( (agora - ult) / 3600 ))h (intervalo ${INTERVALO_H}h); nova consulta após $(date -d "@$((ult + INTERVALO_H * 3600))" '+%d/%m %H:%M' 2>/dev/null || echo "${INTERVALO_H}h")"
        exit 0
    fi
fi

ATUAL="$(versao_atual)"
info "Versão em execução: ${ATUAL:-desconhecida (backend não respondeu)}"

# --- restaurar ---------------------------------------------------------------
if [ "$MODO" = restaurar ]; then
    ULT="$(ls -1t "$DIR"/${BKP_PREFIX}* 2>/dev/null | head -1 || true)"
    [ -n "$ULT" ] || die "nenhum backup ${BKP_PREFIX}* em $DIR"
    confirmar "Restaurar $ULT e reiniciar o DeskFlow?"
    TMP="$(mktemp -d "$DIR/.atualizacao.XXXXXX")"
    trap 'rm -rf "$TMP"' EXIT
    cp -p "$ULT" "$TMP/deskflow_srv"
    instalar_binario "$TMP/deskflow_srv" "restaurado:$(basename "$ULT")" 1
    rm -f "$ULT"
    reiniciar
    exit 0
fi

# --- origem: manifesto do site ou zip local ---------------------------------
NOVA=""; URL=""; SHA=""
if [ -z "$ARQUIVO" ]; then
    MAN="$(curl -fsS -m "$([ "$AUTO" = 1 ] && echo 15 || echo 60)" "$MANIFEST_URL")" || die "não consegui ler $MANIFEST_URL (sem internet? use --arquivo)"
    read -r NOVA URL SHA < <(printf '%s' "$MAN" | python3 -c 'import json,sys
m=json.load(sys.stdin)
print(m.get("version",""), m.get("url",""), m.get("sha256","").lower())') \
        || die "manifesto ilegível"
    [ -n "$NOVA" ] && [ -n "$SHA" ] || die "manifesto incompleto (version/sha256)"
    case "$URL" in https://*) ;; *) die "manifesto com url não-https: $URL" ;; esac
    info "Versão disponível: $NOVA"
else
    [ -f "$ARQUIVO" ] || die "arquivo não encontrado: $ARQUIVO (precisa estar visível no container, ex.: /opt/deskflow)"
fi

if [ "$MODO" = verificar ]; then
    if [ -n "$NOVA" ] && [ -n "$ATUAL" ] && maior "$NOVA" "$ATUAL"; then
        echo "Há atualização: $ATUAL → $NOVA. Rode: docker exec -it deskflow-2610 atualizar-deskflow"
    elif [ -z "$ATUAL" ]; then
        echo "Versão em execução desconhecida; a disponível é ${NOVA:-?}."
    else
        echo "Nada a atualizar."
    fi
    exit 0
fi

if [ -n "$NOVA" ] && [ -n "$ATUAL" ] && ! maior "$NOVA" "$ATUAL" && [ "$FORCAR" = 0 ]; then
    marcar_verificacao
    echo "Já está na versão mais recente ($ATUAL). Use --forcar para reinstalar."
    exit 0
fi

confirmar "Atualizar o DeskFlow${NOVA:+ para $NOVA} e reiniciar o container?"

TMP="$(mktemp -d "$DIR/.atualizacao.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ZIP="$ARQUIVO"
if [ -z "$ZIP" ]; then
    ZIP="$TMP/deploy.zip"
    info "Baixando $URL"
    # --auto vai para o log do container: sem barra de progresso.
    curl -fL $([ "$AUTO" = 1 ] && echo -sS) --retry 3 --connect-timeout 30 -m 3600 -o "$ZIP" "$URL" || die "falha no download"
    GOT="$(sha256sum "$ZIP" | cut -d' ' -f1)"
    [ "$GOT" = "$SHA" ] || die "SHA-256 não confere (esperado $SHA, obtido $GOT) — nada foi alterado"
    info "SHA-256 conferido"
fi

# Extrai só o binário Linux (raiz do zip: deploy-deploy/deskflow_srv) e confere
# que é um executável ELF de 64 bits de tamanho plausível.
python3 - "$ZIP" "$TMP/deskflow_srv" <<'PY' || die "zip inválido ou sem deskflow_srv — nada foi alterado"
import sys, zipfile, shutil
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z:
    names = [n for n in z.namelist() if n.rstrip("/").split("/")[-1] == "deskflow_srv" and n.count("/") <= 1]
    if not names:
        sys.exit("deskflow_srv ausente no zip")
    with z.open(sorted(names, key=len)[0]) as i, open(dst, "wb") as o:
        shutil.copyfileobj(i, o)
with open(dst, "rb") as f:
    head = f.read(5)
import os
if head != b"\x7fELF\x02" or os.path.getsize(dst) < 10 * 1024 * 1024:
    sys.exit("deskflow_srv extraído não parece um binário Linux 64 bits")
PY

instalar_binario "$TMP/deskflow_srv" "${NOVA:-$(basename "$ZIP")}"
[ -z "$NOVA" ] || marcar_verificacao
info "Binário instalado${NOVA:+ ($NOVA)}. Para desfazer: docker exec -it deskflow-2610 atualizar-deskflow --restaurar"
[ "$AUTO" = 1 ] || reiniciar
