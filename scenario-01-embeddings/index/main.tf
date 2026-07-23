resource "opensearch_index" "chunks" {
  name      = var.opensearch_index_name
  index_knn = true

  mappings = jsonencode({
    properties = {
      chunk_id   = { type = "integer" }
      source_key = { type = "keyword" }
      text       = { type = "text" }
      embedding = {
        type      = "knn_vector"
        dimension = var.embed_dimensions
      }
      domain    = { type = "keyword" }
      timestamp = { type = "date" }
    }
  })
}
