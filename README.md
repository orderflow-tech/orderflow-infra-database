# OrderFlow Database Infrastructure

Este repositório contém a infraestrutura como código (IaC) para o banco de dados gerenciável do sistema OrderFlow, utilizando AWS RDS com PostgreSQL.

## Visão Geral

A infraestrutura do banco de dados foi projetada para fornecer alta disponibilidade, segurança, escalabilidade e facilidade de manutenção para o sistema OrderFlow.

### Componentes Principais

- **AWS RDS PostgreSQL**: Banco de dados relacional gerenciado
- **VPC Dedicada**: Rede isolada para o banco de dados
- **Security Groups**: Controle de acesso granular
- **Secrets Manager**: Armazenamento seguro de credenciais
- **CloudWatch**: Monitoramento e alertas
- **Automated Backups**: Backups automáticos com retenção configurável

## Justificativa da Escolha do PostgreSQL

### Por que PostgreSQL?

O **PostgreSQL** foi escolhido como o sistema de gerenciamento de banco de dados (SGBD) para o OrderFlow pelos seguintes motivos:

#### 1. **Conformidade ACID**

O PostgreSQL oferece conformidade total com as propriedades ACID (Atomicidade, Consistência, Isolamento e Durabilidade), essenciais para um sistema de pedidos onde a integridade transacional é crítica. Cada pedido, pagamento e atualização de status deve ser processado de forma confiável e consistente.

#### 2. **Suporte a Tipos de Dados Complexos**

- **JSONB**: Permite armazenar dados semi-estruturados (como itens de pedido, metadados de pagamento) com indexação eficiente
- **Arrays**: Útil para armazenar listas de IDs ou tags
- **Enums**: Perfeito para status de pedido, tipos de pagamento, etc.
- **UUID**: Identificadores únicos globais para entidades distribuídas

#### 3. **Performance e Escalabilidade**

- **Índices avançados**: B-tree, Hash, GiST, GIN para otimização de queries complexas
- **Particionamento de tabelas**: Permite escalar horizontalmente conforme o volume de pedidos cresce
- **Consultas paralelas**: Melhora a performance em operações de leitura intensiva
- **Materialized Views**: Cache de consultas complexas para relatórios

#### 4. **Extensibilidade**

- **pg_stat_statements**: Análise de performance de queries
- **pgcrypto**: Criptografia de dados sensíveis
- **PostGIS**: Caso seja necessário adicionar funcionalidades de geolocalização no futuro

#### 5. **Compatibilidade com Microsserviços**

- **Transações distribuídas**: Suporte a two-phase commit
- **Replicação**: Suporte a read replicas para separar leitura e escrita
- **Connection pooling**: Integração com PgBouncer para gerenciar conexões eficientemente

#### 6. **Custo-Benefício**

- **Open-source**: Sem custos de licenciamento
- **AWS RDS**: Gerenciamento automatizado reduz custos operacionais
- **Comunidade ativa**: Amplo suporte e documentação

#### 7. **Maturidade e Confiabilidade**

- Mais de 30 anos de desenvolvimento
- Utilizado por grandes empresas (Apple, Instagram, Spotify)
- Histórico comprovado de estabilidade e segurança

### Comparação com Outras Opções

| Característica | PostgreSQL | MySQL | MongoDB | DynamoDB |
|----------------|------------|-------|---------|----------|
| ACID Compliance | ✅ Total | ✅ Parcial | ❌ Eventual | ❌ Eventual |
| Tipos Complexos | ✅ JSONB, Arrays | ⚠️ JSON | ✅ Documentos | ⚠️ Limitado |
| Transações | ✅ Completas | ✅ Básicas | ⚠️ Limitadas | ⚠️ Limitadas |
| Escalabilidade | ✅ Vertical/Horizontal | ✅ Vertical | ✅ Horizontal | ✅ Horizontal |
| Custo | ✅ Baixo | ✅ Baixo | ⚠️ Médio | ⚠️ Alto |
| Maturidade | ✅ Alta | ✅ Alta | ⚠️ Média | ⚠️ Média |

## Modelagem de Dados

### Diagrama Entidade-Relacionamento (DER)

```
┌─────────────────┐         ┌─────────────────┐
│    CLIENTE      │         │   CATEGORIA     │
├─────────────────┤         ├─────────────────┤
│ id (PK)         │         │ id (PK)         │
│ cpf (UNIQUE)    │         │ nome            │
│ nome            │         │ descricao       │
│ email           │         │ ativo           │
│ telefone        │         │ created_at      │
│ created_at      │         │ updated_at      │
│ updated_at      │         └─────────────────┘
└─────────────────┘                  │
         │                           │
         │ 1                         │ 1
         │                           │
         │ N                         │ N
         ▼                           ▼
┌─────────────────┐         ┌─────────────────┐
│     PEDIDO      │◄────────│    PRODUTO      │
├─────────────────┤    N    ├─────────────────┤
│ id (PK)         │         │ id (PK)         │
│ cliente_id (FK) │         │ categoria_id(FK)│
│ numero_pedido   │         │ nome            │
│ status          │         │ descricao       │
│ valor_total     │         │ preco           │
│ observacoes     │         │ imagem_url      │
│ created_at      │         │ ativo           │
│ updated_at      │         │ created_at      │
└─────────────────┘         │ updated_at      │
         │                  └─────────────────┘
         │ 1                         ▲
         │                           │
         │ N                         │ N
         ▼                           │
┌─────────────────┐                 │
│  ITEM_PEDIDO    │─────────────────┘
├─────────────────┤
│ id (PK)         │
│ pedido_id (FK)  │
│ produto_id (FK) │
│ quantidade      │
│ preco_unitario  │
│ subtotal        │
│ observacoes     │
│ created_at      │
└─────────────────┘
         │
         │ 1
         │
         │ 1
         ▼
┌─────────────────┐
│   PAGAMENTO     │
├─────────────────┤
│ id (PK)         │
│ pedido_id (FK)  │
│ metodo          │
│ status          │
│ valor           │
│ transaction_id  │
│ qr_code         │
│ paid_at         │
│ created_at      │
│ updated_at      │
└─────────────────┘
```

### Descrição das Tabelas

#### CLIENTE
Armazena informações dos clientes que fazem pedidos na lanchonete.

| Campo | Tipo | Descrição | Constraints |
|-------|------|-----------|-------------|
| id | UUID | Identificador único | PRIMARY KEY |
| cpf | VARCHAR(11) | CPF do cliente | UNIQUE, NOT NULL |
| nome | VARCHAR(255) | Nome completo | NOT NULL |
| email | VARCHAR(255) | Email do cliente | UNIQUE |
| telefone | VARCHAR(20) | Telefone de contato | |
| created_at | TIMESTAMP | Data de criação | NOT NULL, DEFAULT NOW() |
| updated_at | TIMESTAMP | Data de atualização | NOT NULL, DEFAULT NOW() |

**Índices:**
- `idx_cliente_cpf` em `cpf` (UNIQUE)
- `idx_cliente_email` em `email`

#### CATEGORIA
Categorias de produtos (Lanche, Acompanhamento, Bebida, Sobremesa).

| Campo | Tipo | Descrição | Constraints |
|-------|------|-----------|-------------|
| id | UUID | Identificador único | PRIMARY KEY |
| nome | VARCHAR(100) | Nome da categoria | UNIQUE, NOT NULL |
| descricao | TEXT | Descrição da categoria | |
| ativo | BOOLEAN | Categoria ativa | NOT NULL, DEFAULT TRUE |
| created_at | TIMESTAMP | Data de criação | NOT NULL, DEFAULT NOW() |
| updated_at | TIMESTAMP | Data de atualização | NOT NULL, DEFAULT NOW() |

**Índices:**
- `idx_categoria_nome` em `nome` (UNIQUE)
- `idx_categoria_ativo` em `ativo`

#### PRODUTO
Produtos disponíveis para pedido.

| Campo | Tipo | Descrição | Constraints |
|-------|------|-----------|-------------|
| id | UUID | Identificador único | PRIMARY KEY |
| categoria_id | UUID | Referência à categoria | FOREIGN KEY, NOT NULL |
| nome | VARCHAR(255) | Nome do produto | NOT NULL |
| descricao | TEXT | Descrição do produto | |
| preco | DECIMAL(10,2) | Preço do produto | NOT NULL, CHECK > 0 |
| imagem_url | VARCHAR(500) | URL da imagem | |
| ativo | BOOLEAN | Produto ativo | NOT NULL, DEFAULT TRUE |
| created_at | TIMESTAMP | Data de criação | NOT NULL, DEFAULT NOW() |
| updated_at | TIMESTAMP | Data de atualização | NOT NULL, DEFAULT NOW() |

**Índices:**
- `idx_produto_categoria` em `categoria_id`
- `idx_produto_ativo` em `ativo`
- `idx_produto_nome` em `nome`

#### PEDIDO
Pedidos realizados pelos clientes.

| Campo | Tipo | Descrição | Constraints |
|-------|------|-----------|-------------|
| id | UUID | Identificador único | PRIMARY KEY |
| cliente_id | UUID | Referência ao cliente | FOREIGN KEY |
| numero_pedido | VARCHAR(20) | Número sequencial | UNIQUE, NOT NULL |
| status | VARCHAR(50) | Status do pedido | NOT NULL, CHECK IN (...) |
| valor_total | DECIMAL(10,2) | Valor total | NOT NULL, CHECK >= 0 |
| observacoes | TEXT | Observações do pedido | |
| created_at | TIMESTAMP | Data de criação | NOT NULL, DEFAULT NOW() |
| updated_at | TIMESTAMP | Data de atualização | NOT NULL, DEFAULT NOW() |

**Status possíveis:** `RECEBIDO`, `EM_PREPARACAO`, `PRONTO`, `FINALIZADO`, `CANCELADO`

**Índices:**
- `idx_pedido_cliente` em `cliente_id`
- `idx_pedido_numero` em `numero_pedido` (UNIQUE)
- `idx_pedido_status` em `status`
- `idx_pedido_created_at` em `created_at`

#### ITEM_PEDIDO
Itens individuais de cada pedido.

| Campo | Tipo | Descrição | Constraints |
|-------|------|-----------|-------------|
| id | UUID | Identificador único | PRIMARY KEY |
| pedido_id | UUID | Referência ao pedido | FOREIGN KEY, NOT NULL |
| produto_id | UUID | Referência ao produto | FOREIGN KEY, NOT NULL |
| quantidade | INTEGER | Quantidade do produto | NOT NULL, CHECK > 0 |
| preco_unitario | DECIMAL(10,2) | Preço no momento | NOT NULL, CHECK > 0 |
| subtotal | DECIMAL(10,2) | Quantidade × Preço | NOT NULL, CHECK >= 0 |
| observacoes | TEXT | Observações do item | |
| created_at | TIMESTAMP | Data de criação | NOT NULL, DEFAULT NOW() |

**Índices:**
- `idx_item_pedido` em `pedido_id`
- `idx_item_produto` em `produto_id`

#### PAGAMENTO
Informações de pagamento dos pedidos.

| Campo | Tipo | Descrição | Constraints |
|-------|------|-----------|-------------|
| id | UUID | Identificador único | PRIMARY KEY |
| pedido_id | UUID | Referência ao pedido | FOREIGN KEY, NOT NULL, UNIQUE |
| metodo | VARCHAR(50) | Método de pagamento | NOT NULL |
| status | VARCHAR(50) | Status do pagamento | NOT NULL, CHECK IN (...) |
| valor | DECIMAL(10,2) | Valor do pagamento | NOT NULL, CHECK > 0 |
| transaction_id | VARCHAR(255) | ID da transação | UNIQUE |
| qr_code | TEXT | QR Code para pagamento | |
| paid_at | TIMESTAMP | Data do pagamento | |
| created_at | TIMESTAMP | Data de criação | NOT NULL, DEFAULT NOW() |
| updated_at | TIMESTAMP | Data de atualização | NOT NULL, DEFAULT NOW() |

**Status possíveis:** `PENDENTE`, `APROVADO`, `RECUSADO`, `CANCELADO`

**Índices:**
- `idx_pagamento_pedido` em `pedido_id` (UNIQUE)
- `idx_pagamento_status` em `status`
- `idx_pagamento_transaction` em `transaction_id` (UNIQUE)

### Estratégias de Otimização

#### 1. Indexação
- Índices em chaves estrangeiras para otimizar JOINs
- Índices em campos frequentemente usados em WHERE e ORDER BY
- Índices parciais para status ativos

#### 2. Particionamento
Para ambientes de alto volume, a tabela `PEDIDO` pode ser particionada por data:

```sql
CREATE TABLE pedido_2024_01 PARTITION OF pedido
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

#### 3. Materialized Views
Para relatórios de vendas e análises:

```sql
CREATE MATERIALIZED VIEW mv_vendas_diarias AS
SELECT 
    DATE(created_at) as data,
    COUNT(*) as total_pedidos,
    SUM(valor_total) as valor_total
FROM pedido
WHERE status = 'FINALIZADO'
GROUP BY DATE(created_at);
```

#### 4. Connection Pooling
Utilização de PgBouncer para gerenciar conexões eficientemente.

## Estrutura do Projeto

```
orderflow-infra-database/
├── terraform/
│   ├── main.tf               # Recursos principais (RDS, VPC, etc.)
│   ├── variables.tf          # Variáveis configuráveis
│   ├── outputs.tf            # Outputs da infraestrutura
│   └── terraform.tfvars.example  # Exemplo de configuração
├── .github/
│   └── workflows/
│       └── deploy.yml        # Pipeline CI/CD
├── migrations/               # Scripts de migração do banco
│   ├── 001_initial_schema.sql
│   └── README.md
└── README.md                 # Este arquivo
```

## Pré-requisitos

- Terraform 1.7.0 ou superior
- AWS CLI configurado
- Conta AWS com permissões adequadas
- GitHub Actions configurado (para CI/CD)

## Configuração Local

### 1. Configurar Variáveis

Crie um arquivo `terraform/terraform.tfvars`:

```hcl
aws_region              = "us-east-1"
environment             = "dev"
project_name            = "orderflow"
vpc_cidr                = "10.1.0.0/16"
database_subnet_count   = 2
db_name                 = "orderflowdb"
db_username             = "orderflow_admin"
db_instance_class       = "db.t3.micro"
db_allocated_storage    = 20
db_max_allocated_storage = 100
backup_retention_period = 7
multi_az                = false
create_read_replica     = false
```

### 2. Inicializar Terraform

```bash
cd terraform
terraform init
```

### 3. Planejar o Deploy

```bash
terraform plan
```

### 4. Aplicar a Infraestrutura

```bash
terraform apply
```

### 5. Obter Credenciais

```bash
# Endpoint do banco
terraform output db_instance_endpoint

# ARN do secret com credenciais
terraform output db_credentials_secret_arn

# Obter credenciais do Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw db_credentials_secret_arn) \
  --query SecretString \
  --output text | jq .
```

## CI/CD com GitHub Actions

### Secrets Necessários

Configure os seguintes secrets no GitHub:

- `AWS_ACCESS_KEY_ID`: Chave de acesso AWS
- `AWS_SECRET_ACCESS_KEY`: Chave secreta AWS
- `INFRACOST_API_KEY`: API key do Infracost (opcional)

### Jobs do Pipeline

1. **terraform-validate**: Valida a sintaxe e configuração
2. **security-scan**: Executa Checkov e Trivy para análise de segurança
3. **terraform-plan**: Gera plano de execução (apenas em PRs)
4. **terraform-apply**: Aplica a infraestrutura (apenas em push para main/develop)
5. **cost-estimation**: Estima custos com Infracost (opcional)

## Conectando ao Banco de Dados

### Via psql

```bash
# Obter credenciais do Secrets Manager
SECRET_ARN=$(cd terraform && terraform output -raw db_credentials_secret_arn)
DB_CREDS=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text)

# Extrair valores
DB_HOST=$(echo $DB_CREDS | jq -r .host)
DB_PORT=$(echo $DB_CREDS | jq -r .port)
DB_NAME=$(echo $DB_CREDS | jq -r .dbname)
DB_USER=$(echo $DB_CREDS | jq -r .username)
DB_PASS=$(echo $DB_CREDS | jq -r .password)

# Conectar
PGPASSWORD=$DB_PASS psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME
```

### Via Connection String

```bash
# Obter connection string
cd terraform
terraform output -raw connection_string

# Adicionar senha manualmente
postgresql://orderflow_admin:<PASSWORD>@<ENDPOINT>:5432/orderflowdb
```

### Via Aplicação Node.js

```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: {
    rejectUnauthorized: false
  }
});

// Testar conexão
pool.query('SELECT NOW()', (err, res) => {
  console.log(err, res);
  pool.end();
});
```

## Monitoramento

### CloudWatch Alarms

O Terraform configura automaticamente alarmes para:

- **CPU Utilization**: Alerta quando CPU > 80%
- **Freeable Memory**: Alerta quando memória < 1GB
- **Free Storage Space**: Alerta quando armazenamento < 10GB

### Logs

Os logs do PostgreSQL são exportados para CloudWatch:
- `/aws/rds/instance/orderflow-db-{environment}/postgresql`
- `/aws/rds/instance/orderflow-db-{environment}/upgrade`

### Performance Insights

Habilitado por padrão com retenção de 7 dias para análise de performance de queries.

## Backup e Recuperação

### Backups Automáticos

- **Retenção**: 7 dias (dev), 30 dias (production)
- **Janela de backup**: 03:00-04:00 UTC
- **Snapshots**: Criados automaticamente

### Restauração

```bash
# Listar snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier orderflow-db-production

# Restaurar de snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier orderflow-db-restored \
  --db-snapshot-identifier <snapshot-id>
```

## Segurança

### Boas Práticas Implementadas

- ✅ Criptografia em repouso (storage encrypted)
- ✅ Criptografia em trânsito (SSL/TLS)
- ✅ Credenciais no Secrets Manager
- ✅ Security Groups restritivos
- ✅ VPC dedicada
- ✅ Backups automáticos
- ✅ Multi-AZ (production)
- ✅ Deletion protection (production)
- ✅ Enhanced monitoring
- ✅ Performance Insights
- ✅ Logs no CloudWatch

## Troubleshooting

### Erro de Conexão

1. Verificar security groups
2. Verificar se a aplicação está na mesma VPC ou se há VPC peering configurado
3. Verificar credenciais no Secrets Manager

### Performance Lenta

1. Consultar Performance Insights
2. Analisar queries lentas nos logs
3. Verificar índices nas tabelas
4. Considerar aumentar o instance class

### Espaço em Disco

O RDS tem auto-scaling habilitado até o limite de `db_max_allocated_storage`.

## Custos Estimados

### Ambiente de Desenvolvimento

- **RDS db.t3.micro**: ~$15/mês
- **Storage (20GB)**: ~$2/mês
- **Backups**: ~$2/mês
- **Total**: ~$19/mês

### Ambiente de Produção

- **RDS db.t3.small (Multi-AZ)**: ~$60/mês
- **Storage (100GB)**: ~$10/mês
- **Backups (30 dias)**: ~$10/mês
- **Read Replica**: ~$30/mês
- **Total**: ~$110/mês

*Valores aproximados e sujeitos a alterações*

## Contribuindo

1. Crie uma branch a partir de `develop`
2. Faça suas alterações
3. Execute `terraform fmt` e `terraform validate`
4. Abra um Pull Request para `develop`
5. Aguarde a revisão e aprovação

## Licença

MIT

## Suporte

Para questões e suporte, abra uma issue no repositório.
