-- OrderFlow Database Initial Schema
-- PostgreSQL 16.x
-- Author: OrderFlow Team
-- Date: 2025-10-01

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pg_stat_statements for query analysis
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- =============================================================================
-- TABLES
-- =============================================================================

-- Table: CLIENTE
-- Description: Stores customer information
CREATE TABLE IF NOT EXISTS cliente (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cpf VARCHAR(11) NOT NULL UNIQUE,
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    telefone VARCHAR(20),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_cpf_length CHECK (LENGTH(cpf) = 11),
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Table: CATEGORIA
-- Description: Product categories (Lanche, Acompanhamento, Bebida, Sobremesa)
CREATE TABLE IF NOT EXISTS categoria (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(100) NOT NULL UNIQUE,
    descricao TEXT,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table: PRODUTO
-- Description: Available products for ordering
CREATE TABLE IF NOT EXISTS produto (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    categoria_id UUID NOT NULL,
    nome VARCHAR(255) NOT NULL,
    descricao TEXT,
    preco DECIMAL(10,2) NOT NULL,
    imagem_url VARCHAR(500),
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_produto_categoria FOREIGN KEY (categoria_id) 
        REFERENCES categoria(id) ON DELETE RESTRICT,
    CONSTRAINT chk_preco_positivo CHECK (preco > 0)
);

-- Table: PEDIDO
-- Description: Customer orders
CREATE TABLE IF NOT EXISTS pedido (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cliente_id UUID,
    numero_pedido VARCHAR(20) NOT NULL UNIQUE,
    status VARCHAR(50) NOT NULL,
    valor_total DECIMAL(10,2) NOT NULL,
    observacoes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (cliente_id) 
        REFERENCES cliente(id) ON DELETE SET NULL,
    CONSTRAINT chk_status_valido CHECK (status IN (
        'RECEBIDO', 'EM_PREPARACAO', 'PRONTO', 'FINALIZADO', 'CANCELADO'
    )),
    CONSTRAINT chk_valor_total_positivo CHECK (valor_total >= 0)
);

-- Table: ITEM_PEDIDO
-- Description: Individual items in each order
CREATE TABLE IF NOT EXISTS item_pedido (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pedido_id UUID NOT NULL,
    produto_id UUID NOT NULL,
    quantidade INTEGER NOT NULL,
    preco_unitario DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    observacoes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_item_pedido FOREIGN KEY (pedido_id) 
        REFERENCES pedido(id) ON DELETE CASCADE,
    CONSTRAINT fk_item_produto FOREIGN KEY (produto_id) 
        REFERENCES produto(id) ON DELETE RESTRICT,
    CONSTRAINT chk_quantidade_positiva CHECK (quantidade > 0),
    CONSTRAINT chk_preco_unitario_positivo CHECK (preco_unitario > 0),
    CONSTRAINT chk_subtotal_positivo CHECK (subtotal >= 0)
);

-- Table: PAGAMENTO
-- Description: Payment information for orders
CREATE TABLE IF NOT EXISTS pagamento (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pedido_id UUID NOT NULL UNIQUE,
    metodo VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    valor DECIMAL(10,2) NOT NULL,
    transaction_id VARCHAR(255) UNIQUE,
    qr_code TEXT,
    paid_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_pagamento_pedido FOREIGN KEY (pedido_id) 
        REFERENCES pedido(id) ON DELETE CASCADE,
    CONSTRAINT chk_status_pagamento_valido CHECK (status IN (
        'PENDENTE', 'APROVADO', 'RECUSADO', 'CANCELADO'
    )),
    CONSTRAINT chk_valor_pagamento_positivo CHECK (valor > 0)
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Cliente indexes
CREATE INDEX idx_cliente_cpf ON cliente(cpf);
CREATE INDEX idx_cliente_email ON cliente(email);
CREATE INDEX idx_cliente_created_at ON cliente(created_at);

-- Categoria indexes
CREATE INDEX idx_categoria_nome ON categoria(nome);
CREATE INDEX idx_categoria_ativo ON categoria(ativo);

-- Produto indexes
CREATE INDEX idx_produto_categoria ON produto(categoria_id);
CREATE INDEX idx_produto_ativo ON produto(ativo);
CREATE INDEX idx_produto_nome ON produto(nome);
CREATE INDEX idx_produto_categoria_ativo ON produto(categoria_id, ativo);

-- Pedido indexes
CREATE INDEX idx_pedido_cliente ON pedido(cliente_id);
CREATE INDEX idx_pedido_numero ON pedido(numero_pedido);
CREATE INDEX idx_pedido_status ON pedido(status);
CREATE INDEX idx_pedido_created_at ON pedido(created_at DESC);
CREATE INDEX idx_pedido_status_created_at ON pedido(status, created_at DESC);

-- Item Pedido indexes
CREATE INDEX idx_item_pedido ON item_pedido(pedido_id);
CREATE INDEX idx_item_produto ON item_pedido(produto_id);

-- Pagamento indexes
CREATE INDEX idx_pagamento_pedido ON pagamento(pedido_id);
CREATE INDEX idx_pagamento_status ON pagamento(status);
CREATE INDEX idx_pagamento_transaction ON pagamento(transaction_id);

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Function: update_updated_at_column
-- Description: Automatically updates the updated_at column
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER trg_cliente_updated_at
    BEFORE UPDATE ON cliente
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_categoria_updated_at
    BEFORE UPDATE ON categoria
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_produto_updated_at
    BEFORE UPDATE ON produto
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_pedido_updated_at
    BEFORE UPDATE ON pedido
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_pagamento_updated_at
    BEFORE UPDATE ON pagamento
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function: generate_numero_pedido
-- Description: Generates a unique order number
CREATE OR REPLACE FUNCTION generate_numero_pedido()
RETURNS VARCHAR(20) AS $$
DECLARE
    novo_numero VARCHAR(20);
    contador INTEGER;
BEGIN
    -- Format: ORD-YYYYMMDD-NNNN
    SELECT COUNT(*) + 1 INTO contador
    FROM pedido
    WHERE DATE(created_at) = CURRENT_DATE;
    
    novo_numero := 'ORD-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(contador::TEXT, 4, '0');
    
    RETURN novo_numero;
END;
$$ LANGUAGE plpgsql;

-- Function: calculate_item_subtotal
-- Description: Calculates the subtotal for an order item
CREATE OR REPLACE FUNCTION calculate_item_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    NEW.subtotal = NEW.quantidade * NEW.preco_unitario;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for item_pedido subtotal calculation
CREATE TRIGGER trg_item_pedido_subtotal
    BEFORE INSERT OR UPDATE ON item_pedido
    FOR EACH ROW
    EXECUTE FUNCTION calculate_item_subtotal();

-- Function: update_pedido_valor_total
-- Description: Updates the total value of an order when items change
CREATE OR REPLACE FUNCTION update_pedido_valor_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pedido
    SET valor_total = (
        SELECT COALESCE(SUM(subtotal), 0)
        FROM item_pedido
        WHERE pedido_id = COALESCE(NEW.pedido_id, OLD.pedido_id)
    )
    WHERE id = COALESCE(NEW.pedido_id, OLD.pedido_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger for updating order total
CREATE TRIGGER trg_update_pedido_valor_total
    AFTER INSERT OR UPDATE OR DELETE ON item_pedido
    FOR EACH ROW
    EXECUTE FUNCTION update_pedido_valor_total();

-- =============================================================================
-- INITIAL DATA
-- =============================================================================

-- Insert default categories
INSERT INTO categoria (nome, descricao) VALUES
    ('Lanche', 'Lanches e hambúrgueres'),
    ('Acompanhamento', 'Acompanhamentos como batatas fritas, onion rings, etc.'),
    ('Bebida', 'Bebidas variadas'),
    ('Sobremesa', 'Sobremesas e doces')
ON CONFLICT (nome) DO NOTHING;

-- =============================================================================
-- VIEWS
-- =============================================================================

-- View: pedidos_com_detalhes
-- Description: Orders with customer and payment details
CREATE OR REPLACE VIEW pedidos_com_detalhes AS
SELECT 
    p.id,
    p.numero_pedido,
    p.status,
    p.valor_total,
    p.observacoes,
    p.created_at,
    p.updated_at,
    c.id AS cliente_id,
    c.nome AS cliente_nome,
    c.cpf AS cliente_cpf,
    c.email AS cliente_email,
    pg.id AS pagamento_id,
    pg.metodo AS pagamento_metodo,
    pg.status AS pagamento_status,
    pg.transaction_id AS pagamento_transaction_id,
    pg.paid_at AS pagamento_paid_at
FROM pedido p
LEFT JOIN cliente c ON p.cliente_id = c.id
LEFT JOIN pagamento pg ON p.id = pg.pedido_id;

-- View: produtos_por_categoria
-- Description: Active products grouped by category
CREATE OR REPLACE VIEW produtos_por_categoria AS
SELECT 
    c.id AS categoria_id,
    c.nome AS categoria_nome,
    p.id AS produto_id,
    p.nome AS produto_nome,
    p.descricao AS produto_descricao,
    p.preco AS produto_preco,
    p.imagem_url AS produto_imagem_url
FROM categoria c
INNER JOIN produto p ON c.id = p.categoria_id
WHERE c.ativo = TRUE AND p.ativo = TRUE
ORDER BY c.nome, p.nome;

-- =============================================================================
-- GRANTS
-- =============================================================================

-- Grant permissions to application user
-- Note: Replace 'orderflow_app' with your actual application user
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO orderflow_app;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO orderflow_app;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO orderflow_app;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE cliente IS 'Stores customer information';
COMMENT ON TABLE categoria IS 'Product categories';
COMMENT ON TABLE produto IS 'Available products for ordering';
COMMENT ON TABLE pedido IS 'Customer orders';
COMMENT ON TABLE item_pedido IS 'Individual items in each order';
COMMENT ON TABLE pagamento IS 'Payment information for orders';

COMMENT ON COLUMN cliente.cpf IS 'Customer CPF (Brazilian tax ID) - 11 digits';
COMMENT ON COLUMN pedido.numero_pedido IS 'Unique order number in format ORD-YYYYMMDD-NNNN';
COMMENT ON COLUMN pedido.status IS 'Order status: RECEBIDO, EM_PREPARACAO, PRONTO, FINALIZADO, CANCELADO';
COMMENT ON COLUMN pagamento.status IS 'Payment status: PENDENTE, APROVADO, RECUSADO, CANCELADO';

-- =============================================================================
-- COMPLETION
-- =============================================================================

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'OrderFlow database schema created successfully!';
    RAISE NOTICE 'Database version: 1.0.0';
    RAISE NOTICE 'Migration: 001_initial_schema.sql';
END $$;
