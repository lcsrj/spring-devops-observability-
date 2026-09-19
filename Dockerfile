# =============================================================================
#  DevOps Observability Control Center - Dockerfile MULTISTAGE
#
#  Estagio 1 (build)   : imagem com JDK 21 + Maven. Baixa dependencias, roda os
#                        testes e compila o .jar executavel.
#  Estagio 2 (runtime) : imagem enxuta com apenas o JRE 21 (Alpine). Recebe
#                        somente o .jar - sem codigo-fonte, sem Maven e sem
#                        ferramentas de compilacao.
#
#  Verificacao da separacao:
#    docker run --rm --entrypoint sh <imagem> -c "ls /app; which mvn javac || echo 'sem toolchain'"
# =============================================================================

# -----------------------------------------------------------------------------
# ESTAGIO 1 - BUILD
# -----------------------------------------------------------------------------
FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /workspace

# 1) Dependencias primeiro: a camada so e invalidada quando o pom.xml muda,
#    aproveitando o cache do Docker entre builds.
COPY pom.xml ./
RUN mvn -B -ntp dependency:go-offline

# 2) Codigo-fonte
COPY src ./src

# 3) Compila e EXECUTA OS TESTES. Se qualquer teste falhar, o build da imagem falha.
RUN mvn -B -ntp clean package

# 4) Conferencia explicita de que o artefato esperado foi gerado.
RUN test -f /workspace/target/app.jar \
    && echo "Artefato gerado:" && ls -lh /workspace/target/app.jar

# -----------------------------------------------------------------------------
# ESTAGIO 2 - RUNTIME
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21.0.12_8-jre-alpine AS runtime

LABEL org.opencontainers.image.title="DevOps Observability Control Center" \
      org.opencontainers.image.description="Aplicacao Spring Boot com Actuator, Micrometer/Prometheus e logs GELF para Graylog" \
      org.opencontainers.image.source="https://github.com/lcsrj/spring-devops-observability" \
      org.opencontainers.image.licenses="MIT"

# Usuario sem privilegios: o processo Java nunca roda como root.
RUN addgroup -S spring && adduser -S -G spring spring

WORKDIR /app

# Unico artefato copiado do estagio de build: o .jar.
COPY --from=build /workspace/target/app.jar /app/app.jar

RUN chown -R spring:spring /app
USER spring

ENV JAVA_OPTS="-XX:MaxRAMPercentage=70 -XX:+UseSerialGC -Djava.security.egd=file:/dev/./urandom" \
    SPRING_PROFILES_ACTIVE=docker

EXPOSE 8080

# wget vem do busybox da imagem Alpine - nenhum pacote extra e necessario.
HEALTHCHECK --interval=10s --timeout=5s --start-period=45s --retries=12 \
    CMD wget -q -O - http://127.0.0.1:8080/actuator/health/readiness | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
