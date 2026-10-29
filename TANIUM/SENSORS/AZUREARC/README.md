# Sensor Tanium: Azure Arc Agent Status

Sensor somente leitura que informa o estado do **Azure Arc Connected Machine Agent** (`azcmagent`) em endpoints **Windows** e **Linux**: se está instalado, a versão, se a máquina está de fato **conectada ao Azure** (e não só com o agente instalado) e o estado dos serviços do agente.

Criado para validar o onboarding feito pelos pacotes `DC-Sentinel-SIEM-WIN` e `DC-Sentinel-SIEM-LNX`, já que os sensores padrão (`Service Details`, `Running Service`, `Installed Applications`) mostram apenas o estado dos serviços, não a conexão com o Azure.

## Resumo

| Propriedade | Valor |
|---|---|
| Nome | `Azure Arc Agent Status` |
| Categoria | Software |
| Plataformas | Windows (PowerShell), Linux (shell) |
| Delimitador | `|` |
| Max age | 1800 s |
| Tipo de valor | String |
| Parâmetros | nenhum |

## Colunas

| # | Coluna | Descrição |
|---|---|---|
| 0 | Agent Installed | `Yes` ou `No` |
| 1 | Agent Version | Versão do agente, ou `Not installed` |
| 2 | Agent Status | `Connected`, `Disconnected`, `Expired` ou `Not installed`. Em falha do `azcmagent show`, `Error: azcmagent show failed or timed out` |
| 3 | Resource Name | Nome do recurso no Azure (`N/A` se não conectado) |
| 4 | Resource Group | Resource Group no Azure |
| 5 | Subscription ID | ID da assinatura do Azure |
| 6 | Tenant ID | ID do tenant do Azure |
| 7 | Last Heartbeat | Último heartbeat reportado pelo agente |
| 8 | Services | `himds=...;arcproxy=...;extensionservice=...;gcarcservice=...` (mesmos quatro nomes nas duas plataformas) |

Mapeamento dos serviços: `himds` = `himds` (Windows) / `himdsd.service` (Linux); `arcproxy` = `ArcProxy` / `arcproxyd.service`; `extensionservice` = `ExtensionService` / `extd.service`; `gcarcservice` = `GCArcService` / `gcad.service`. Serviço inexistente aparece como `notfound`.

## Como funciona

- **Windows:** localiza `azcmagent.exe` em `%ProgramW6432%\AzureConnectedMachineAgent`, roda `azcmagent show -j` com timeout de 20 s e, se falhar, interpreta o texto de `azcmagent show`. Estado dos serviços via `Get-Service`.
- **Linux:** procura `/opt/azcmagent/bin/azcmagent` e depois o `azcmagent` no PATH. Roda `azcmagent show -j` (com `timeout 20` quando disponível) e cai para o texto se necessário. Estado dos serviços via `systemctl`.
- **Somente leitura:** não executa `connect`, `disconnect`, alterações de configuração nem chamadas de rede próprias. Se o agente não está instalado, devolve `No` e `Not installed` sem erro.

## Como importar no Tanium

1. No console, abra a criação de sensores (Administration > Content > Sensors > New, ou o painel de Write Sensor).
2. Nome: `Azure Arc Agent Status`. Categoria: `Software`. Delimitador: `|`.
3. Crie as 9 colunas (todas `String`) na ordem da tabela acima.
4. Cole o script de cada plataforma (abaixo) e defina o max age em 1800 s.
5. Salve e teste primeiro em poucas máquinas, por exemplo `Get "Computer Name" and "Azure Arc Agent Status" from all machines with "Computer Name" equals "<host>"`.

> A primeira avaliação logo após salvar pode voltar com 0 linhas por alguns minutos, até o sensor ser distribuído aos clientes.

## Considerações de segurança

- O sensor executa um binário de terceiros (`azcmagent`) com privilégios elevados em cada endpoint, a cada avaliação. Valide em um grupo pequeno antes de ampliar.
- As colunas **Subscription ID** e **Tenant ID** expõem identificadores do Azure. Considere ocultá-las ou restringir quem pode ver o sensor se os resultados forem exportados ou exibidos em dashboards.
- **Last Heartbeat** muda em cada máquina e reduz a agregação de resultados. Se você só precisa contar conectadas, pode remover essa coluna.
- Não cobre macOS, AIX nem Solaris.
- Não foram encontradas credenciais nos scripts. Revise de novo antes de publicar.
