USE peppol_invoices;

CREATE TABLE IF NOT EXISTS invoices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  peppol_xml LONGTEXT NOT NULL,
  status ENUM('new', 'processing', 'processed', 'error') NOT NULL DEFAULT 'new',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  processed_at TIMESTAMP NULL,
  error_message TEXT
);
