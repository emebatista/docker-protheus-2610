# docker-protheus-2610
Protheus 12.1.2610 em containers Docker (Postgres, DBAccess, License Server 3.7.2, AppServer 26.3, SmartView 3.11), **gerenciado pelo DeskFlow Control** — o painel web que sobe junto e controla todos os serviços.

📘 **Guia completo em PDF** (download, primeira subida, DeskFlow, Protheus, SmartView, operação e problemas comuns): [docs/Guia-Protheus-2610-Docker-DeskFlow.pdf](docs/Guia-Protheus-2610-Docker-DeskFlow.pdf)

Procedimentos:
1. Instalar o <b>Docker</b> ( https://www.docker.com/products/docker-desktop/ ). <b>IMPORTANTE:</b> Se você possui um Mac com chip M1/M2, desabilite no Docker a opção "Use Rosetta for x86_64/amd64 emulation on Apple Silicon", caso contrário os conteiners podem não subir. 
2. Criar uma pasta e copiar para ela este repositório (botão <b>Code → Download ZIP</b>, ou ```git clone https://github.com/emebatista/docker-protheus-2610.git```). São necessários o <b>docker-compose.yml</b>, o <b>conf.inf</b> e a pasta <b>deskflow/</b> (configuração do DeskFlow Control).
3. Abrir o terminal dentro dessa pasta e dar os comandos: <br>
```docker login``` <br>
e depois <br>
```docker compose up -d``` <br> Se as imagens já estiverem em cache e quiser forçar baixá-las de novo, o comando é <br> ```docker compose up -d --pull always```<br>
No Docker Desktop, o grupo de containers chama-se <b>protheus2610</b> (nome fixo no compose; o DeskFlow depende dele). Na primeira subida o Docker cria os volumes `pgdata` (banco já restaurado, vem pronto na imagem), `protheus12`, `protheus12-license` e `dbaccess-multi` a partir das imagens: é neles que ficam o banco, INIs, RPO, dicionários e logs, e é por eles que o DeskFlow enxerga tudo.
4. Abrir o <b>DeskFlow Control</b> em <b>http://localhost:8073</b> (usuário ```admin```, senha ```msadm``` — troque no primeiro acesso). A topologia "Protheus 2610 (Docker)" já vem configurada com os seis serviços; confira por ali que todos os serviços estão Running e use-o para parar, iniciar e reiniciar os serviços daqui em diante — não precisa de `docker compose` no dia a dia.
5. Acessar o <b>Protheus</b> através do smartclient através na porta <b>1234</b>. O nome do ambiente é <b>P2610</b>. O banco já vem restaurado na imagem; na primeira subida aguarde 1 a 2 minutos (cópia do cluster para o volume e subida do AppServer) antes de entrar. 
6. Acessar o <b>Protheus WebApp</b> através do navegador do endereço <b>http://localhost:4321</b>.
7. Usuário: Admin , senha: ```T0tvs@2026``` (senha da release 2610; na 2510 era ```$$T0tvs$$```)
8. Primeiro entre em SIGACFG / Cadastros / Configuração do Tipo de Ambiente -> Definir como "Desenvolvimento"
9. O SmartView já vem instalado e pré-configurado em uma máquina virtual chamada smartview-2610 com as portas 7017 e 7019 expostas:
    - Para verificar o status do serviço do SmartView: http://localhost:7019/diagnostic
    - Para alterar configuração do SmartView, criação de conectores, consultas específicas e relatórios, o endereço é http://localhost:7017/
    - Para reconfigurar o SmartView: http://localhost:7019/startup
    - Dentro do Protheus, para poder acessar os relatórios no novo formato, é preciso acessar SIGACFG / Ambiente / Cadastros / Configuração SmartView. Depois escolher a opção "token protheus". É IMPORTANTE informar na url o IP real da máquina (não localhost nem 127.0.0.1), informe no formato http://ip:7017 e clicar 'Testar Conexão'. Exemplo: http://192.168.0.10:7017.
    
    Para todas as configurações de IP no smartview, informe o IP do computador onde ele estará instalado:

![alt text](image-8.png)    

![alt text](image-9.png)

![alt text](image-4.png)
    
![alt text](image-6.png)

![alt text](image-7.png)

    - Para acessar o WebMonitor: http://localhost:1234/webmonitor
    - DeskFlow Control: http://localhost:8073 , usuário ```admin``` , senha ```msadm```
    
Notas:
1) Para utilizar o Protheus na interface sem a porta multiprotocolo, utilize o ambiente P2610D. Esta opção é útil quando se precisa compilar customizações desenvolvidas em ADVPL/TLPP.
2) Para apagar todas as imagens, volumes e containers que não estão rodando, o comando para apagar tudo e manter apenas os volumes do banco de dados e a pasta system_temp, o comando é :<br> ```docker system prune --all --volumes --force``` 
3) Parar, iniciar e reiniciar serviços: pelo DeskFlow (aba Serviços da topologia, ou Modo Exclusivo). Para baixar de novo a imagem de um container e recriá-lo:<br>
```docker compose up -d --no-deps --force-recreate --pull always protheus```<br>
(idem para `license`, `db`, `smartview`, `dbaccess`, `deskflow`). Os volumes nomeados preservam INIs, RPO e dados entre recriações; para voltar ao conteúdo original da imagem, remova o volume (`docker volume rm protheus2610_protheus12`) antes de recriar.
4) Se já possuir conteiners com a versão 2410 ou 2510, é preciso que estas vm estejam paradas para que as da versão 2610 possam subir, uma vez que usam as mesmas portas.
5) Existe um container para acesso exclusivo (protheus-2610-exclusivo), que não sobe serviços de Rest e permite alterar a base em modo exclusivo (porta 1235 / WebApp 4322). Use o botão <b>Ativar Exclusivo</b> do DeskFlow: ele para os serviços normais, sobe o exclusivo e, ao desativar, volta tudo ao normal.

---

<h2>Gerencie o Protheus com o DeskFlow Control</h2>

Este projeto vem preparado para ser operado pelo **DeskFlow Control**, uma ferramenta de gestão de ambientes Protheus/AppServer que roda no próprio servidor (Linux ou Windows) e controla serviços, ambientes, INIs, RPOs, patches e dicionários por uma interface web. Aqui ele roda como mais um container e enxerga o Protheus, o DBAccess, o License Server e o SmartView como serviços.

![DeskFlow - Monitor](deskflow-1-monitor.jpg)

<h3>Por que usar o DeskFlow no dia a dia</h3>

- **Um painel para tudo**: iniciar, parar e reiniciar cada serviço (ou todos de uma vez) com status em tempo real, portas em uso e consumo de memória. Chega de `docker compose stop/start` na mão.
- **Modo exclusivo com um clique**: para os serviços normais e sobe o `protheus-2610-exclusivo` (sem REST) para manutenções que exigem acesso exclusivo à base; desativa e tudo volta ao normal.
- **Ambientes e RPO sob controle**: promover RPO entre ambientes com histórico e rollback, comparar ambientes, gerar hash do RPO, aplicar patches (PTM/PAK/UPD) com defrag opcional e compilar fontes ADVPL/TLPP.
- **Atualização de dicionário**: upload dos arquivos de dicionário, backup automático do `systemload`, execução do UPDDISTR e restauração.
- **INIs sem medo**: edição dos `appserver.ini` com validação, comparação de seções, detecção de chaves duplicadas e conversão de encoding.
- **Auditoria da topologia**: checagens automáticas (INIs legíveis, ambiente principal único, sourcepaths válidos, ordem de start/stop, compilador configurado…) com semáforo verde/amarelo/vermelho.
- **Visão executiva**: saúde geral de todas as topologias, serviços operacionais, riscos de auditoria e atividade operacional do período.
- **Logs ao vivo**: `console.log` do AppServer e `dbaccess.log` direto na tela, com filtro por palavra-chave e download.
- **Agendador**: tarefas recorrentes (restart de serviços, promoções, patches) por cron ou intervalo.
- **Rastreabilidade**: log de todas as ações com usuário, hora, topologia, serviço e resultado; notificações em tempo real.
- **Usuários e permissões**: grupos, permissões por topologia/serviço/ambiente, integração opcional com Active Directory.
- **Multi-servidor**: controla também serviços remotos (SSH no Linux, SCM/WMI no Windows) a partir de uma única console.

![DeskFlow - Serviços](deskflow-2-servicos.jpg)

![DeskFlow - Ambientes](deskflow-3-ambientes.jpg)

![DeskFlow - Visão executiva](deskflow-4-visao-executiva.jpg)

![DeskFlow - Auditoria](deskflow-5-auditoria.jpg)

![DeskFlow - Log de ações](deskflow-6-log-acoes.jpg)

<h3>Já vem no compose</h3>

O DeskFlow faz parte do `docker-compose.yml`: o serviço `deskflow` (um único container, `deskflow-2610`, com o nginx da interface e o backend) sobe com os demais no `docker compose up -d`. Ele monta os mesmos volumes que os containers do Protheus (`/protheus12`, `/dbaccess/multi`), por isso INIs, RPO, `console.log` e `dbaccess.ini` são os mesmos arquivos que o AppServer usa — editar INI, promover RPO, aplicar patch e ver log funcionam sobre o ambiente real. A pasta `deskflow/` do repositório guarda a configuração (`config.json` com a topologia pronta, `deskflow.ini`) e, depois da primeira subida, os dados e a licença; ela fica na sua máquina e sobrevive a recriações dos containers.

Primeiro acesso: **http://localhost:8073**, usuário ```admin```, senha ```msadm``` (troque em Configuração → Usuários).

<h3>Licença</h3>

O DeskFlow Control é um produto licenciado por servidor. Esta demonstração em containers mostra o produto completo; para usar no seu ambiente (VM ou servidor físico, Linux ou Windows), solicite uma licença de avaliação ou comercial em **https://deskflow.com.br** (menu Contato) ou pelo e-mail `contato@deskflow.com.br`, informando nome da empresa e quantidade de servidores. A licença é aplicada nos campos `tenant_code`, `tenant_name` e `tenant_authorization` do `deskflow/deskflow.ini`.


ATENÇÃO!
O banco de dados já vem restaurado dentro da imagem `postgres-2610` (volume `pgdata`). Só haverá restore do dump na primeira subida se você montar uma pasta vazia em `/var/lib/postgresql/seed` em vez do volume nomeado; nesse caso aguarde o log do container do postgres mostrar `Restore Finished`.

---

<h2>Versões deste pacote (publicado em 17/10/2026)</h2>

| Imagem | Tag | Conteúdo |
|---|---|---|
| `emebatista/postgres-2610` | 1.0.0 / latest | PostgreSQL 15.14 com a base 12.1.2610 já restaurada (encoding WIN1252) |
| `emebatista/license-server-2610` | 1.0.0 / latest | License Server 3.7.2 |
| `emebatista/protheus-dbaccess-2610` | 1.0.0 / latest | DBAccess 26.1.0.0 |
| `emebatista/protheus-2610` | 1.0.0 / latest | AppServer 26.3.0.0, RPO/Lib 12.1.2610 (Lib 20261016), WebApp 26.0.0, compilador do DeskFlow com includes, ambientes P2610 / P2610_COMPILA / P2610_DEBUG; usada também pelo acesso exclusivo |
| `emebatista/smartview-2610` | 1.0.0 / latest | SmartView 3.11.4 (Agent 3.5.4) |
| `emebatista/deskflow-2610` | 1.0.0 / latest | DeskFlow Control 3.0.250 com nginx embutido, topologias e licença de demonstração pré-configuradas |

Para atualizar uma instalação existente para as imagens mais recentes: `docker compose pull` seguido de `docker compose up -d` (os volumes nomeados preservam banco, RPO, INIs e a configuração do DeskFlow). Para conferir o que está publicado: https://hub.docker.com/u/emebatista

### Atualizar só o DeskFlow (sem esperar nova imagem)

O DeskFlow recebe versões com mais frequência que a imagem. Para instalar a mais recente (backend e interface — a interface vem embutida no binário) direto no container:

```sh
docker exec -it deskflow-2610 atualizar-deskflow --verificar   # mostra versão atual e disponível
docker exec -it deskflow-2610 atualizar-deskflow               # atualiza e reinicia o DeskFlow
docker exec -it deskflow-2610 atualizar-deskflow --restaurar   # volta a versão anterior
```

O comando baixa a versão de https://deskflow.com.br, confere o SHA-256 antes de trocar qualquer arquivo, guarda backup do binário anterior em `./deskflow/` e reinicia o container (a interface volta em ~15 s). Sem internet no servidor: baixe o zip indicado em https://deskflow.com.br/updates/latest.json, coloque em `./deskflow/` e rode `atualizar-deskflow --arquivo /opt/deskflow/<arquivo>.zip`.

**Atualização automática:** na subida do container o DeskFlow confere o site e, havendo versão nova, instala antes de iniciar (sem internet ou com falha, sobe com a versão que já tem). A consulta ao site acontece no máximo uma vez a cada 24 h, por mais que o container reinicie — e a tentativa conta mesmo sem internet (a próxima consulta só após o intervalo). Imagem nova consulta na primeira subida. O intervalo muda com `DESKFLOW_AUTO_UPDATE_HORAS` no `environment`; a verificação manual (`atualizar-deskflow`) não tem limite. Para desligar, troque `DESKFLOW_AUTO_UPDATE=1` por `0` no serviço `deskflow` do `docker-compose.yml` e rode `docker compose up -d`. Depois de um `--restaurar`, a versão restaurada fica fixa até a próxima atualização manual.

A versão instalada assim é mantida nas reinicializações. Um `docker compose pull` + `up -d` que traga imagem nova volta a usar o DeskFlow da imagem.

Imagem `deskflow-2610` 1.0.0 (ainda sem o comando): rode a partir desta pasta

```sh
docker exec -i deskflow-2610 bash -s -- --sim < atualizar-deskflow.sh
```

Documentação completa: [guia do usuário em PDF](docs/Guia-Protheus-2610-Docker-DeskFlow.pdf).
