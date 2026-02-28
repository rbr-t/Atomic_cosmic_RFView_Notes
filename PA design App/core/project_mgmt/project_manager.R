# Project Manager - Core System
# Handles project lifecycle management

library(R6)
library(DBI)
library(uuid)

ProjectManager <- R6Class("ProjectManager",
  private = list(
    db_pool = NULL
  ),
  
  public = list(
    initialize = function(db_pool) {
      private$db_pool <- db_pool
      self$init_schema()
    },
    
    init_schema = function() {
      # Create projects table if not exists
      query <- "
        CREATE TABLE IF NOT EXISTS projects (
          id UUID PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          architecture_type VARCHAR(50),
          topology VARCHAR(50),
          frequency_min NUMERIC,
          frequency_max NUMERIC,
          frequency NUMERIC,
          target_pout NUMERIC,
          target_gain NUMERIC,
          target_pae NUMERIC,
          current_phase VARCHAR(50) DEFAULT 'concept',
          status VARCHAR(20) DEFAULT 'active',
          tags TEXT[],
          metadata JSONB,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      "
      
      tryCatch({
        dbExecute(private$db_pool, query)
      }, error = function(e) {
        message("Note: Projects table may already exist or DB not connected")
      })
    },
    
    create_project = function(name, architecture_type = "Class-A", 
                             frequency = 2.4, target_pout = 30,
                             topology = NULL, tags = NULL) {
      project_id <- UUIDgenerate()
      
      query <- "
        INSERT INTO projects (id, name, architecture_type, frequency, target_pout, topology, tags)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, name, created_at
      "
      
      tryCatch({
        result <- dbGetQuery(
          private$db_pool, 
          query,
          params = list(
            project_id, name, architecture_type, 
            frequency, target_pout, topology, tags
          )
        )
        return(result)
      }, error = function(e) {
        # Fallback for demo without database
        message("DB not available, using mock data")
        return(data.frame(
          id = project_id,
          name = name,
          created_at = Sys.time()
        ))
      })
    },
    
    get_project = function(project_id) {
      query <- "SELECT * FROM projects WHERE id = $1"
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query, params = list(project_id))
        return(result)
      }, error = function(e) {
        return(data.frame())
      })
    },
    
    get_all_projects = function() {
      query <- "SELECT * FROM projects ORDER BY updated_at DESC"
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query)
        return(result)
      }, error = function(e) {
        # Mock data for demo
        return(data.frame(
          id = c(UUIDgenerate(), UUIDgenerate(), UUIDgenerate()),
          name = c("5G PA - 3.5GHz", "WiFi 6E PA - 6GHz", "Sub-6 GaN PA"),
          architecture_type = c("Class-AB", "Class-E", "Doherty"),
          frequency = c(3.5, 6.0, 2.4),
          target_pout = c(43, 30, 50),
          current_phase = c("simulation", "layout", "concept"),
          status = c("active", "active", "planning"),
          created_at = Sys.time() - c(10, 5, 1) * 86400,
          updated_at = Sys.time() - c(1, 2, 1) * 3600
        ))
      })
    },
    
    update_project = function(project_id, updates) {
      # Build dynamic UPDATE query
      set_clause <- paste(names(updates), "= $", 1:length(updates), sep = "", collapse = ", ")
      query <- sprintf("UPDATE projects SET %s, updated_at = CURRENT_TIMESTAMP WHERE id = $%d", 
                      set_clause, length(updates) + 1)
      
      tryCatch({
        dbExecute(private$db_pool, query, params = c(updates, project_id))
        return(TRUE)
      }, error = function(e) {
        message("Update failed: ", e$message)
        return(FALSE)
      })
    },
    
    delete_project = function(project_id) {
      query <- "DELETE FROM projects WHERE id = $1"
      
      tryCatch({
        dbExecute(private$db_pool, query, params = list(project_id))
        return(TRUE)
      }, error = function(e) {
        message("Delete failed: ", e$message)
        return(FALSE)
      })
    },
    
    get_project_milestones = function(project_id) {
      # Milestones: concept → calculation → architecture → simulation → layout → measurement
      milestones <- list(
        list(name = "Concept", status = "completed", date = Sys.time() - 30*86400),
        list(name = "Theoretical Calculation", status = "completed", date = Sys.time() - 25*86400),
        list(name = "Architecture Selection", status = "in_progress", date = NULL),
        list(name = "Simulation", status = "not_started", date = NULL),
        list(name = "Layout", status = "not_started", date = NULL),
        list(name = "Measurement", status = "not_started", date = NULL)
      )
      
      return(milestones)
    }
  )
)
