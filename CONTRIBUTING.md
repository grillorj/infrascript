🤝 Guia de Contribuição – InfraScript

Obrigado por dedicar seu tempo para contribuir com o InfraScript!
Seu envolvimento ajuda a manter este projeto ativo, útil e acessível para toda a comunidade técnica.
Este documento descreve como contribuir, boas práticas e padrões esperados para novos conteúdos e contribuições de código.

⚙️ Sumário

    Antes de Começar
    Como Contribuir
    Diretrizes para Scripts
    Boas Práticas de Código
    Padrões de Referência e Documentação
    Relatando Problemas
    Revisão e Aprovação
    Código de Conduta

🧩 Antes de Começar

Antes de enviar qualquer contribuição:

    Leia o README.md – Entenda o propósito e a estrutura do projeto.
    Verifique as Issues abertas – O que já está sendo discutido ou trabalhado.
    Evite duplicação – Se quiser propor algo novo, verifique se já existe script similar.
    Teste localmente – Certifique-se de que sua alteração funciona em diferentes sistemas operacionais (Linux, Windows, macOS).

Se você é novo em contribuições open-source, o artigo Como fazer seu primeiro pull request no GitHub pode ajudar.
🛠️ Como Contribuir

Há várias formas de apoiar o projeto, e todas são bem-vindas:
🧾 1. Melhorando a Documentação

    Corrija erros de digitação, traduções ou formatações.
    Adicione exemplos de uso prático, tutoriais e explicações mais ricas.

💡 2. Criando Novos Scripts

    Adicione scripts úteis que resolvam problemas comuns em infraestrutura, DevOps ou automação.
    Mantenha o estilo consistente com os scripts existentes.

🧹 3. Corrigindo Bugs ou Otimizando Scripts

    Identifique e corrija erros de funcionamento ou de lógica.
    Melhore desempenho, legibilidade e portabilidade entre sistemas.

🧠 4. Sugerindo Ideias

    Abra uma Issue com o tipo [SUGESTÃO] e descreva sua ideia.
    Explique a motivação, possível benefício e uma breve proposta de implementação.

💻 Diretrizes para Scripts

Cada novo script adicionado deve seguir o formato e padrões abaixo:
📂 Localização

Adicione o script na pasta correspondente à sua linguagem:

scripts/

├── bash/

├── python/

├── powershell/

└── shell/

🧾 Cabeçalho Padrão

Inclua um cabeçalho no início do script, seguindo este modelo:
Exemplo para Bash:


#!/bin/bash
# ==========================================================
# Nome: backup_server.sh
# Descrição: Script para backup automatizado de diretórios
# Autor: Leonardo Silva
# Versão: 1.2
# Data: 10/11/2025
# Dependências: tar, gzip
# Uso: ./backup_server.sh /origem /destino
# ==========================================================


Exemplo para Python:

#!/usr/bin/env python3

"""
Nome: monitor_procs.py
Descrição: Monitora processos e alerta caso excedam thresholds.
Autor: Leonardo Silva
Versão: 2.0
Data: 10/11/2025
Dependências: psutil, smtplib
Uso: python3 monitor_procs.py --process nginx
"""

📘 Documentação Complementar

    Inclua um arquivo README.md dentro da pasta do script (quando for um módulo maior).
    Documente parâmetros, exemplos e mensagens de saída.

🧪 Testes

    Se possível, adicione um arquivo de teste em tests/nomedoscript_test.sh (ou .py).
    Teste em múltiplos ambientes antes do PR.

🧹 Boas Práticas de Código

Para manter a qualidade e padronização:
Linguagem 	                Recomendações
Bash/Shell 	                Use set -e para abortar em erros; comente blocos críticos; siga a nomenclatura minúsculas_com_underscores.
Python 	                    Obedeça o PEP 8; mantenha funções curtas e documentadas; prefira argparse para parâmetros.
PowerShell 	                Use verbos padrão (Get, Set, Remove, Test); inclua Param() no início; siga convenções de nomenclatura PascalCase.
Todos 	                    Evite hardcodes; use variáveis configuráveis e mensagens compreensíveis.

    💡 Dica: scripts legíveis, modulares e bem comentados são mais fáceis de manter e aprender.

✍️ Padrões de Referência e Documentação

    Idiomas aceitos: português e/ou inglês (preferencialmente bilíngue).
    Convenções de commits:
        feat: nova funcionalidade
        fix: correção de bug
        docs: alteração de documentação
        refactor: melhoria de código sem alterar comportamento
        test: adição/modificação de testes
        chore: tarefas gerais

Exemplo:
git commit -m "feat(bash): adiciona script para backup incremental"

    Pull Requests (PRs) devem ter:
        Descrição objetiva.
        Lista de mudanças (bullet points).
        Ambiente de teste usado.
        Prints ou logs de saída (se aplicável).

🐞 Relatando Problemas

Ao encontrar um erro, use a aba Issues no GitHub e inclua:

    Sistema operacional (ex.: Ubuntu 24.04, Windows 11, macOS 14).
    Versão do script ou commit hash.
    Passos para reproduzir o erro.
    Saída obtida vs. esperada.
    Logs, prints ou trechos de código relevantes (em blocos Markdown).

Crie o título no formato:

    [BUG] Falha ao executar backup_server.sh em macOS

Se for sugestão de melhoria:

    [SUGESTÃO] Adicionar suporte a logs rotativos no script de backup

🔎 Revisão e Aprovação

    Todo Pull Request é avaliado e testado manualmente antes de merge.
    Revisores podem solicitar ajustes de estilo, clareza ou estrutura.
    Quando aprovado:
        A contribuição é unida à branch principal.
        Seu nome é listado como colaborador no arquivo CREDITS.md.
    Caso o PR seja rejeitado, o motivo será explicado e sugestões serão oferecidas.

⚖️ Código de Conduta

Queremos um ambiente colaborativo, inclusivo e respeitoso.
Ao contribuir, você concorda em:

    Respeitar a diversidade e opiniões técnicas diferentes.
    Ser claro e cortês em comentários e revisões.
    Evitar comportamento ofensivo, sarcasmo excessivo e linguagem discriminatória.
    Contribuir com empatia — todos estão aprendendo algo.

Violação das normas poderá levar à remoção de comentários, PRs ou banimento da comunidade em casos graves.
🧡 Agradecimento

Cada contribuição é um avanço coletivo.
Mesmo pequenas melhorias — uma correção de texto, um comentário extra, um bloco de código mais limpo — fazem enorme diferença.

    “A automação cresce quando há colaboração. Obrigado por fazer parte dessa comunidade!”

📫 Dúvidas ou sugestões diretas?
Entre em contato via GitHub Discussions ou pelo site oficial infrascript.wordpress.com.
