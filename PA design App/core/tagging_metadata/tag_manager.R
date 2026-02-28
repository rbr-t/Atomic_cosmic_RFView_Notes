# Tag Manager - Core System
# Manages tagging and metadata for all entities

library(R6)
library(DBI)
library(jsonlite)

TagManager <- R6Class("TagManager",
  private = list(
    db_pool = NULL
  ),
  
  public = list(
    initialize = function(db_pool) {
      private$db_pool <- db_pool
      self$init_schema()
    },
    
    init_schema = function() {
      query <- "
        CREATE TABLE IF NOT EXISTS tags (
          id UUID PRIMARY KEY,
          entity_type VARCHAR(50) NOT NULL,
          entity_id UUID NOT NULL,
          tag_name VARCHAR(100) NOT NULL,
          tag_value TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(entity_type, entity_id, tag_name)
        );
        
        CREATE INDEX IF NOT EXISTS idx_tags_entity ON tags(entity_type, entity_id);
        CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(tag_name);
      "
      
      tryCatch({
        dbExecute(private$db_pool, query)
      }, error = function(e) {
        message("Note: Tags table may already exist or DB not connected")
      })
    },
    
    add_tag = function(entity_type, entity_id, tag_name, tag_value = NULL) {
      tag_id <- UUIDgenerate()
      
      query <- "
        INSERT INTO tags (id, entity_type, entity_id, tag_name, tag_value)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (entity_type, entity_id, tag_name) 
        DO UPDATE SET tag_value = $5, created_at = CURRENT_TIMESTAMP
      "
      
      tryCatch({
        dbExecute(
          private$db_pool,
          query,
          params = list(tag_id, entity_type, entity_id, tag_name, tag_value)
        )
        return(TRUE)
      }, error = function(e) {
        message("Tag add failed: ", e$message)
        return(FALSE)
      })
    },
    
    get_tags = function(entity_type, entity_id) {
      query <- "SELECT tag_name, tag_value FROM tags WHERE entity_type = $1 AND entity_id = $2"
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query, params = list(entity_type, entity_id))
        return(result)
      }, error = function(e) {
        return(data.frame())
      })
    },
    
    remove_tag = function(entity_type, entity_id, tag_name) {
      query <- "DELETE FROM tags WHERE entity_type = $1 AND entity_id = $2 AND tag_name = $3"
      
      tryCatch({
        dbExecute(private$db_pool, query, params = list(entity_type, entity_id, tag_name))
        return(TRUE)
      }, error = function(e) {
        return(FALSE)
      })
    },
    
    search_by_tag = function(tag_name, tag_value = NULL) {
      if (is.null(tag_value)) {
        query <- "SELECT entity_type, entity_id FROM tags WHERE tag_name = $1"
        params <- list(tag_name)
      } else {
        query <- "SELECT entity_type, entity_id FROM tags WHERE tag_name = $1 AND tag_value = $2"
        params <- list(tag_name, tag_value)
      }
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query, params = params)
        return(result)
      }, error = function(e) {
        return(data.frame())
      })
    },
    
    get_all_tags = function(entity_type = NULL) {
      if (is.null(entity_type)) {
        query <- "SELECT DISTINCT tag_name FROM tags ORDER BY tag_name"
        params <- list()
      } else {
        query <- "SELECT DISTINCT tag_name FROM tags WHERE entity_type = $1 ORDER BY tag_name"
        params <- list(entity_type)
      }
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query, params = params)
        return(result$tag_name)
      }, error = function(e) {
        return(character(0))
      })
    }
  )
)
