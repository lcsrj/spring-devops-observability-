# Contexto completo do projeto

> Documento de referência gerado em **17/09/2026**.
> Projeto: **DevOps Observability Control Center** (`spring-devops-observability`)
> Repositório: **https://github.com/lcsrj/spring-devops-observability**
> Usuário GitHub: **lcsrj**

---

## 1. Resumo executivo

| | |
|---|---|
| **Status geral** | ✅ **Projeto concluído** — validado localmente, publicado no GitHub, pipeline verde, imagem no GHCR |
| **Testes** | 23/23 passando |
| **Auditoria local** | 83/83 verificações |
| **Smoke test** | 28/28 |
| **Pipeline CI/CD** | `conclusion: success` nos 4 jobs |
| **GHCR** | `:latest` · `:1.0.0` · `:main` · `:sha-2db9b29` |
| **Evidências** | 16 arquivos em `docs/evidencias/` |
| **Commits** | 15 commits organizados na branch `main` |

---

## 2. O que é o projeto

Aplicação **Java 21 / Spring Boot 3.5.3** com interface web própria, que serve como painel de
demonstração de uma esteira DevOps/DevSecOps completa:

- **Interface web** (Thymeleaf + CSS/JS próprios, sem CDN) com cards de estado, botões que
  disparam requisições HTTP reais (200/400/500 e rajadas), botões que emitem logs reais nos
  4 níveis, histórico das ações medido no servidor e links da stack;
- **Dockerfile multistage** — estágio 1 com JDK+Maven (baixa dependências, roda testes,
  gera o `.jar`), estágio 2 apenas com JRE recebendo só o `.jar`;
- **Stack local em um único `docker compose up --build`**: app, Prometheus, Grafana,
  MongoDB, OpenSearch, Graylog e `graylog-init`;
- **Métricas** via Actuator + Micrometer em `/actuator/prometheus`, coletadas pelo Prometheus;
- **Grafana** com data source e dashboard de 14 painéis provisionados automaticamente;
- **Logs** via Logback + appender GELF/UDP para o Graylog, com o Input GELF criado
  automaticamente por um serviço idempotente;
- **CI/CD** no GitHub Actions: testes, build multistage, validação da imagem, publicação no
  GHCR e varreduras Trivy.

---

## 3. Como rodar (para quem pegar o projeto agora)

```bash
git clone https://github.com/lcsrj/spring-devops-observability.git
cd spring-devops-observability
docker compose up --build
```

Não é necessário ter Java ou Maven instalados — compilação e testes acontecem dentro do
estágio de build da imagem.

URLs após subir:

| Serviço | URL | Credenciais (laboratório) |
|---|---|---|
| Aplicação | http://localhost:8080 | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | `admin` / `admin123` |
| Graylog | http://localhost:9000 | `admin` / `admin` |

> ⚠️ Nesta máquina a porta **3000 já está ocupada** pela stack `zup-*`. O arquivo `.env`
> local (não versionado) define `GRAFANA_PORT=3001`. Todas as portas são parametrizáveis —
> veja `.env.example`.

Validação:

```bash
./scripts/wait-stack.sh        # espera readiness real (sem sleep cego)
./scripts/smoke-test.sh        # 28 verificações
./scripts/generate-traffic.sh 3
./scripts/verify-stack.sh      # 83 verificações
./scripts/capture-evidence.sh  # gera docs/evidencias/
```

Documentação completa: [`README.md`](README.md) · matriz de requisitos:
[`EVIDENCIAS.md`](EVIDENCIAS.md)

---

## 4. O que foi feito, item por item

### 4.1 Aplicação Spring Boot ✅

- **Endpoints**: `GET /`, `GET /api/status`, `GET /api/history`, `GET /api/demo/ok` (200),
  `GET /api/demo/bad-request` (400), `GET /api/demo/error` (500),
  `POST /api/demo/log/{debug,info,warn,error}`, `POST /api/demo/traffic`.
- **Actuator** com superfície mínima: `health` (com liveness/readiness), `info` e
  `prometheus`. `env`, `beans`, `heapdump`, `threaddump` e `configprops` retornam **404** —
  verificado por teste automatizado.
- **Tags comuns** `application` / `environment` / `version` aplicadas por
  `MeterRegistryCustomizer`, presentes em 100% das séries (inclusive métricas da JVM).
- **Histograma nativo** habilitado para `http.server.requests`, permitindo p95/p99 com
  `histogram_quantile` no Prometheus.
- **Correlation id** por requisição: gerado (ou reaproveitado do header), propagado ao MDC,
  ao header `X-Correlation-Id` da resposta e ao campo `correlation_id` no Graylog.
- **Gerador de tráfego real**: `POST /api/demo/traffic` abre conexões HTTP de verdade contra
  a própria aplicação, com padrão cíclico determinístico de 7×200 / 2×400 / 1×500 (teto de
  200 por rajada). A porta é descoberta em runtime via `WebServerInitializedEvent`, o que faz
  o mesmo código funcionar no container e nos testes com porta aleatória.
- **Histórico** em `ConcurrentLinkedDeque` limitado a 50 entradas, alimentado por
  `HandlerInterceptor` que mede status e duração **no servidor**. Só `/api/demo/**` é
  auditado — o polling de `/api/status` não polui o histórico.

### 4.2 Interface web ✅

Painel Thymeleaf com CSS e JavaScript próprios (zero CDN, zero framework frontend):
cards de estado, seção "Gerar tráfego", seção "Gerar logs", histórico em tabela com pills
coloridas por família de status, links rápidos, estados de loading nos botões, toasts de
sucesso/erro e layout responsivo (testado em 1600px e em largura de telefone).

O indicador "Envio ao Graylog" **não é texto fixo**: a aplicação consulta o Logback
(`root.getAppender("GELF")`) e reporta se o appender está realmente anexado.

### 4.3 Testes ✅ — 23/23

| Classe | Testes |
|---|---|
| `ObservabilityApplicationTests` | 2 — contexto inicializa, propriedades carregadas |
| `StatusEndpointTests` | 9 — interface HTML, `/api/status`, correlation id, health (incluindo a garantia de que ele nao depende de disco do host), info, `/actuator/prometheus` com métricas de JVM/CPU/threads/uptime/HTTP, endpoints administrativos ausentes |
| `DemoEndpointTests` | 7 — 200/400/500, os 4 endpoints de log com contador por nível, histórico, polling fora do histórico, limite do buffer |
| `TrafficGeneratorIntegrationTests` | 5 — servidor HTTP real (`RANDOM_PORT`): porta descoberta, rajada 7/2/1, default, teto de 200, séries 2xx/4xx/5xx no `/actuator/prometheus` |

Rodar sem Maven instalado:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  maven:3.9.9-eclipse-temurin-21 mvn -B -ntp test
```

### 4.4 Dockerfile multistage ✅ (requisito eliminatório)

Medido na imagem realmente construída:

| Verificação | Resultado |
|---|---|
| Estágios `FROM` | 2 (`build`, `runtime`) |
| Estágio 1 | `maven:3.9.9-eclipse-temurin-21`, roda `mvn clean package` (executa os testes) |
| Estágio 2 | `eclipse-temurin:21.0.12_8-jre-alpine` |
| Copiado para o runtime | apenas `/app/app.jar` (29 MB) |
| Imagem de build | 800 MB |
| **Imagem final** | **398 MB** local (descomprimido) · **121 MB** no GHCR (soma das 9 camadas comprimidas) |
| `mvn` / `javac` / `jar` no runtime | **AUSENTES** |
| Arquivos `.java` / `pom.xml` no runtime | **0 / 0** |
| `/root/.m2` no runtime | **ausente** |
| Usuário do processo | `uid=100(spring)` — não-root |

As mesmas checagens rodam no `verify-stack.sh` **e** no job `docker` da pipeline, que falha
se qualquer ferramenta de build vazar para o runtime.

### 4.5 Docker Compose ✅

7 serviços, `networks`, 6 volumes nomeados, healthchecks em 6 serviços, `depends_on` com
`condition`, `restart` policy, variáveis de ambiente e portas documentadas.

Ordem de subida:

```
mongodb (healthy) ─┐
                   ├─> graylog (started) ─> app (healthy) ─> prometheus (healthy) ─> grafana
opensearch (healthy)┘
                     graylog (healthy) ─> graylog-init (exit 0)
```

**Versões fixas, nenhuma tag `latest`** (a pipeline falha se aparecer uma):
Graylog 5.2.11 · MongoDB 6.0.19 · OpenSearch 2.15.0 · Prometheus v2.54.1 ·
Grafana 11.2.0 · curl 8.9.1 · Temurin 21.0.12_8-jre-alpine · Maven 3.9.9.

**Resultado medido:** `docker compose up --build` subiu os 7 serviços `healthy` **de
primeira**, sem nenhuma correção manual.

### 4.6 Prometheus ✅

- `prometheus/prometheus.yml` com scrape de `app:8080/actuator/prometheus` a cada 5s.
- Target `spring-boot-app` = **UP** (confirmado na UI e via `/api/v1/targets`).
- 15 consultas PromQL executadas, todas com valor real: heap usada/máxima/comprometida,
  CPU do processo e do sistema, threads, uptime, total de requisições, RPS, 2xx, 4xx, 5xx,
  latência média, p95 e o contador próprio `app_demo_log_events_total`.

### 4.7 Grafana ✅

- Data source Prometheus provisionado (`grafana/provisioning/datasources/`), health `OK`.
- Dashboard **"Spring Boot — Application Observability"** provisionado automaticamente
  (uid `spring-observability`), configurado como home dashboard — abre direto nele.
- **14 painéis** em 3 linhas: visão geral (status, uptime, total, RPS, latência, threads),
  requisições HTTP (RPS por família 2xx/4xx/5xx, donut por status, latência média/p95/p99,
  requisições por endpoint) e JVM (heap, CPU, threads + não-heap, eventos de log por nível).
- Confirmado via `POST /api/ds/query` que os painéis retornam **dados reais**.

### 4.8 Graylog ✅

- Stack Graylog + MongoDB + OpenSearch, versões compatíveis e fixas.
- **`graylog-init`**: serviço de execução única que espera o Graylog ficar saudável
  (`/api/system/lbstatus`, sem `sleep` cego), verifica se o Input já existe, cria o Input
  GELF UDP 12201 só se necessário, confirma o estado `RUNNING` e encerra com exit 0.
  **Idempotência comprovada**: na segunda subida logou
  `input GELF UDP ja existe - nada a fazer (execucao idempotente)` e a contagem de inputs
  permaneceu 1.
- **Logs medidos no Graylog**: 295 mensagens indexadas —
  **DEBUG 10 · INFO 191 · WARN 63 · ERROR 31**.
- Campos estruturados por mensagem: `timestamp`, `level_name`, `level`, `logger_name`,
  `message`, `full_message` (com stack trace), `application`, `environment`, `version`,
  `correlation_id`, `thread_name`, `source`, `root_cause_class_name`, `demo_level`.

Busca no Graylog: `application:spring-devops-observability AND level_name:ERROR`

### 4.9 Scripts ✅

`scripts/lib.sh` (funções compartilhadas) · `wait-stack.sh` · `generate-traffic.sh` ·
`smoke-test.sh` · `verify-stack.sh` · `capture-evidence.sh`.
Todos retornam exit code ≠ 0 quando uma validação falha e respeitam as portas do `.env`.

### 4.10 Pipeline CI/CD ✅ — verde

4 jobs:

1. **build-and-test** — JDK 21 Temurin com cache Maven, lê a versão do `pom.xml`,
   `mvn compile`, `mvn test`, `mvn package`, publica relatórios Surefire e o `.jar`.
2. **compose-lint** — valida `docker compose config`, confere os 7 serviços obrigatórios e
   **falha se alguma imagem usar `:latest`**.
3. **docker** — Buildx, tags via metadata-action, build multistage, **valida que o runtime
   está enxuto** (sem mvn/javac/jar e sem código-fonte), sobe a aplicação a partir da imagem
   e testa os endpoints (200/400/500 + `/actuator/prometheus`), publica no GHCR.
4. **security-scan** — Trivy (dependências/configuração, segredos e imagem de runtime), com
   `continue-on-error` para nunca bloquear os requisitos obrigatórios.

**Decisão documentada**: a publicação no GHCR ocorre **apenas em push na `main`**. Em Pull
Requests a imagem é construída e validada, mas não publicada, porque o `GITHUB_TOKEN` de PRs
de forks é somente-leitura para `packages` — falharia por permissão, não por qualidade.
Autenticação exclusivamente com `secrets.GITHUB_TOKEN`; **nenhum PAT no repositório**.

### 4.11 GHCR ✅

```
ghcr.io/lcsrj/spring-devops-observability:latest
ghcr.io/lcsrj/spring-devops-observability:1.0.0
ghcr.io/lcsrj/spring-devops-observability:main
ghcr.io/lcsrj/spring-devops-observability:sha-0ccc024
```

Prova no log do CI: a pipeline fez `docker pull` da imagem **de volta do GHCR**, inspecionou
(`ok: sem mvn/javac/jar`, `ok: sem codigo-fonte na imagem final`,
`imagem: [ghcr.io/lcsrj/spring-devops-observability:main] / tamanho: 266707788 bytes`) e
validou os endpoints com a aplicação em execução.

### 4.12 Documentação ✅

- **`README.md`** — visão geral, diagrama Mermaid da arquitetura, execução, URLs,
  credenciais de laboratório, como gerar tráfego, como validar Prometheus / Grafana /
  Graylog (com as PromQL e as queries Lucene prontas), scripts, testes, explicação do
  multistage com os números medidos, pipeline, GHCR, endpoints, estrutura do projeto,
  **15 decisões técnicas justificadas**, tabela de versões e troubleshooting.
- **`EVIDENCIAS.md`** — matriz de 27 requisitos × implementação × validação × evidência,
  resultado da auditoria por seção, prova do multistage e checklist final.
- **`.env.example`** — todas as variáveis documentadas.

### 4.13 Segurança / DevSecOps ✅

- Usuário não-root na imagem de runtime.
- Superfície do Actuator mínima (verificada por teste).
- `.env` no `.gitignore`; apenas `.env.example` versionado.
- **Nenhum token, PAT ou segredo real no repositório.**
- Credenciais de laboratório claramente marcadas como desenvolvimento e documentadas.
- Trivy na pipeline: vulnerabilidades, misconfiguration e **scanner de segredos**.
- Versionamento fixo de todas as imagens.

---

## 5. Bugs reais encontrados e corrigidos

Vale registrar — **todos** foram descobertos por execução real (testes, logs de pipeline,
capturas de tela), nenhum por inspeção de código:

| # | Bug | Como apareceu | Correção |
|---|---|---|---|
| 1 | `@ExceptionHandler(Exception.class)` genérico capturava exceções do Spring MVC e transformava **404 em 500** | Teste `unnecessaryActuatorEndpointsAreNotExposed` esperava 404 e recebeu 500 | `ApiExceptionHandler` passou a estender `ResponseEntityExceptionHandler`; a rede de segurança cobre só `RuntimeException` da aplicação |
| 2 | Contadores de tráfego sempre zerados no `generate-traffic.sh` | Script reportou `2xx=0` mesmo com todas as chamadas 200 | A função rodava em `$( )` (subshell); passou a expor o status em `LAST_CODE` |
| 3 | Busca no Graylog retornava **HTTP 400** | `verify-stack.sh` não achava nenhuma mensagem, embora existissem | Sem `Accept: application/json`, a negociação de conteúdo roteia para o export CSV, que exige `fields`. Header adicionado em `graylog_api()` |
| 4 | Caixa vazia com borda na interface | Visível na captura de tela | `.burst__result { display: flex }` sobrepõe `[hidden]`; adicionada regra `.burst__result[hidden] { display: none }` |
| 5 | `mvn test` do `verify-stack.sh` falhava no Windows | `working directory 'C:/Program Files/Git/workspace' is invalid` | Git Bash converte caminhos; adicionados `host_path_for_docker()` e `docker_run()` com `MSYS_NO_PATHCONV` |
| 6 | Métrica de log intermitentemente "sem dados" | Consulta caía entre dois scrapes | `metric_has_value()` passou a ter retry pelo intervalo de scrape |
| 7 | `aquasecurity/trivy-action@0.28.0` não resolve | CI: `unable to find version` | As tags do repositório usam prefixo `v` |
| 8 | Step do CI falhava com **exit 23** apesar da aplicação responder certo | `curl \| grep -q` com `set -o pipefail`: o `grep -q` fecha o pipe e o produtor morre com Broken pipe | Respostas gravadas em arquivo; `grep` lê o arquivo. Sem pipe algum |
| 9 | Trivy falhava com `429 Too Many Requests` do Maven Central | CI | varredura de configuração passou a usar `trivy config`; vulnerabilidades ficaram no scan da imagem |
| 10 | `/actuator/health` respondia **503** com a aplicação saudável | O `DiskSpaceHealthIndicator` mede o disco do caminho onde o processo roda; o volume havia enchido e, por ser agregado, ele derrubava o health inteiro | Indicador desabilitado (a aplicação não usa disco) e teste novo travando a decisão |
| 11 | `timeout` do host não matava capturas travadas do Chromium | Em Git Bash/MSYS o sinal não chega ao `docker.exe`, que é processo nativo do Windows | Limite de tempo movido para **dentro** do container, com o `timeout` do busybox |
| 12 | Disco de 238 GB enchia repetidamente, levando o Docker com ele | O Chromium headless apontado para a SPA do Graylog **derruba a VM do WSL**; cada crash grava um dump de ~14 GB em `%LOCALAPPDATA%\Temp\wsl-crashes`. O disco cheio derrubava o engine do Docker em seguida — o que parecia ser a causa era a consequência | Captura da interface do Graylog virou **opt-in** (`CAPTURE_GRAYLOG_UI=1`), com o motivo documentado no script. O Graylog continua comprovado por 3 evidências de API |

---

## 6. Incidentes de infraestrutura durante o desenvolvimento

Registrados porque explicam decisões no código e podem se repetir nesta máquina.

### 6.1 Disco cheio derrubou o Docker Desktop (duas vezes)

O disco `C:` chegou a **0 byte livre** e o Docker Desktop passou a responder
`Docker Desktop is unable to start`, travando qualquer comando `docker` e interrompendo a
captura de evidências.

Diagnóstico, na ordem em que foi descoberto:

| Consumidor | Tamanho | Natureza |
|---|---|---|
| **Cache de build do Docker** | **12,4 GB** (9,7 GB recuperáveis) | gerado pelos `docker compose up --build` repetidos |
| `%TEMP%\wsl-crashes` | 5,88 GB → **13,63 GB** | dumps de crash do WSL, gerados *pelo próprio disco cheio* |
| Imagens Docker | 16,2 GB (7,9 GB recuperáveis) | Maven, Temurin, Prometheus, Grafana, MongoDB, OpenSearch, Graylog, curl, Chromium |

O ponto importante é o **ciclo vicioso**: com o disco cheio o WSL começa a despejar dumps de
crash, que enchem mais o disco, que geram mais dumps. A pasta `wsl-crashes` mais que dobrou
em uma hora.

Receita de recuperação, se acontecer de novo:

```bash
# 1. quebrar o ciclo: apagar os dumps de crash (sao apenas diagnostico)
rm -rf "$TEMP/wsl-crashes"

# 2. destravar o Docker (com disco cheio ele fica inutilizavel e nao volta sozinho)
#    encerrar o Docker Desktop -> wsl --shutdown -> iniciar o Docker Desktop

# 3. recuperar o espaco do proprio Docker
docker builder prune -af     # o maior ganho: cache de build
docker image prune -a        # imagens sem container associado
```

E, para evitar o problema: use `docker compose up -d` (sem `--build`) quando a imagem já
existir. Cada `--build` acrescenta camadas ao cache.

### 6.2 Captura de tela do Graylog travava o script

A interface do Graylog é uma SPA que mantém requisições abertas, então o
`--virtual-time-budget` do Chromium headless nunca expirava e o container ficava preso
indefinidamente. Corrigido em `scripts/capture-evidence.sh`:

- `timeout 120` externo em toda captura, com remoção do container preso em caso de falha;
- orçamento de tempo virtual configurável por captura — a do Graylog usa 3s.

### 6.3 Escopo do `gh` local

O token do `gh` nesta máquina tem os escopos `gist`, `read:org`, `repo` e `workflow` — **não
tem `read:packages`**, então a página do pacote no GHCR não pode ser consultada pela API
daqui (HTTP 403). A publicação foi comprovada pelo log do CI, que fez `docker pull` da
imagem de volta do GHCR e a inspecionou. Para habilitar a consulta por API:

```bash
gh auth refresh -h github.com -s read:packages
```

---

## 7. Itens que só podem ser feitos manualmente

Nada disso é requisito do enunciado (que pede evidências "quando possível"), mas se quiser
anexar capturas visuais do GitHub ao trabalho, estas duas precisam de navegador logado:

- [ ] Screenshot da execução verde em
      https://github.com/lcsrj/spring-devops-observability/actions/runs/35260193812
- [ ] Screenshot do pacote em
      https://github.com/lcsrj/spring-devops-observability/pkgs/container/spring-devops-observability

Todas as outras evidências já estão em `docs/evidencias/` e podem ser regeradas a qualquer
momento:

```bash
docker compose up --build -d
./scripts/wait-stack.sh
./scripts/capture-evidence.sh
```

## 8. Mapa dos arquivos

```
spring-devops-observability/
├── .github/workflows/ci-cd.yml          # pipeline: build, test, docker, GHCR, Trivy
├── .dockerignore  .gitignore  .env.example
├── Dockerfile                           # MULTISTAGE (eliminatório)
├── docker-compose.yml                   # 7 serviços
├── pom.xml                              # Spring Boot 3.5.3, Java 21
├── README.md                            # documentação principal
├── EVIDENCIAS.md                        # matriz de requisitos
├── CONTEXTO_E_PENDENCIAS.md             # este documento
├── src/main/java/br/com/devops/observability/
│   ├── config/    AppProperties, MetricsConfig, RestClientConfig, SelfEndpointResolver
│   ├── model/     records de request/response
│   ├── service/   ActionHistoryService, LogDemoService, TrafficGeneratorService
│   └── web/       Home/Status/DemoController, ApiExceptionHandler,
│                  CorrelationIdFilter, ActionAuditInterceptor, WebConfig
├── src/main/resources/
│   ├── application.yml  logback-spring.xml
│   ├── templates/index.html
│   └── static/{css,js,img}/
├── src/test/java/...                    # 23 testes
├── prometheus/prometheus.yml
├── grafana/{provisioning/{datasources,dashboards},dashboards}/
├── graylog/init/create-gelf-input.sh
├── scripts/                             # lib, wait-stack, generate-traffic,
│                                        # smoke-test, verify-stack, capture-evidence
└── docs/evidencias/                     # 16 arquivos (ver seção 6.2)
```

---

## 9. Histórico de commits

Os 9 primeiros commits montam o projeto; os 5 seguintes são correções feitas a partir dos
logs reais da pipeline, até ela ficar verde.

```
docs: evidencias completas de execucao e contexto do projeto
fix(ci): remove flag inexistente do trivy config e torna as varreduras independentes
fix(ci): usa o comando trivy config para a varredura de misconfiguration
fix(ci): separa as varreduras Trivy por responsabilidade
fix(ci): exclui o pom.xml do scan de filesystem do Trivy
fix(ci): adiciona --offline-scan ao Trivy para evitar rate limit do Maven Central
fix(ci): elimina falhas por SIGPIPE e troca a action do Trivy pela imagem oficial
fix(ci): corrige versao da trivy-action e falha por pipefail em curl|grep
docs: README completo e matriz de evidencias
ci: pipeline CI/CD com GitHub Actions e publicacao no GHCR
feat: scripts de validacao e captura de evidencias
feat: stack completa em um unico docker compose
build: Dockerfile multistage (requisito eliminatorio)
test: suite de 23 testes automatizados
feat: interface web do painel de observabilidade
feat: aplicacao Spring Boot com endpoints, metricas e logs GELF
chore: estrutura inicial do projeto Maven
```

---

## 10. Checklist final

| Item | Status |
|---|---|
| Aplicação Spring funciona | ✅ |
| Interface funciona | ✅ |
| Endpoints funcionam | ✅ |
| Testes passam | ✅ 23/23 |
| Dockerfile é multistage | ✅ verificado por inspeção da imagem |
| Imagem Docker compila | ✅ |
| Compose sobe a stack | ✅ de primeira, 7 serviços healthy |
| App fica healthy | ✅ |
| Prometheus coleta a aplicação | ✅ |
| Target está UP | ✅ |
| Grafana tem dashboard provisionado | ✅ 14 painéis |
| Dashboard apresenta métricas reais | ✅ confirmado via API |
| Graylog inicia | ✅ |
| Input configurado automaticamente | ✅ idempotente |
| Logs chegam ao Graylog | ✅ 295 mensagens |
| DEBUG aparece | ✅ 10 |
| INFO aparece | ✅ 191 |
| WARN aparece | ✅ 63 |
| ERROR aparece | ✅ 31 |
| README completo | ✅ |
| Git limpo | ✅ |
| Repositório GitHub criado | ✅ |
| Código enviado | ✅ |
| GitHub Actions executado | ✅ |
| Pipeline verde | ✅ `conclusion: success` nos 4 jobs |
| Imagem publicada no GHCR | ✅ 4 tags, validada por `docker pull` no próprio CI |
| Evidências organizadas | ✅ `docs/evidencias/` |

**Nenhuma pendência bloqueante.** O único item opcional restante são as capturas de tela
das páginas do GitHub (seção 7), que exigem navegador logado.
