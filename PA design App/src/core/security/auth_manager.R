# Authentication Manager - Core System
# Handles user authentication and authorization

library(R6)

AuthManager <- R6Class("AuthManager",
  private = list(
    db_pool = NULL,
    sessions = list()
  ),
  
  public = list(
    initialize = function(db_pool = NULL) {
      private$db_pool <- db_pool
      self$init_schema()
    },
    
    init_schema = function() {
      if (is.null(private$db_pool)) return(FALSE)
      
      query <- "
        CREATE TABLE IF NOT EXISTS users (
          id UUID PRIMARY KEY,
          username VARCHAR(255) UNIQUE NOT NULL,
          email VARCHAR(255) UNIQUE NOT NULL,
          password_hash VARCHAR(255) NOT NULL,
          role VARCHAR(50) DEFAULT 'designer',
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          last_login TIMESTAMP
        )
      "
      
      tryCatch({
        dbExecute(private$db_pool, query)
        return(TRUE)
      }, error = function(e) {
        message("Note: Users table may already exist or DB not connected")
        return(FALSE)
      })
    },
    
    authenticate = function(username, password) {
      # For now, mock authentication (will implement properly with bcrypt)
      # In production, use proper password hashing
      
      if (username == "demo" && password == "demo") {
        session_id <- paste0("session_", as.integer(Sys.time()))
        
        private$sessions[[session_id]] <- list(
          user_id = "demo_user",
          username = username,
          role = "admin",
          login_time = Sys.time()
        )
        
        return(list(
          success = TRUE,
          session_id = session_id,
          user = list(username = username, role = "admin")
        ))
      }
      
      return(list(
        success = FALSE,
        message = "Invalid credentials"
      ))
    },
    
    validate_session = function(session_id) {
      if (session_id %in% names(private$sessions)) {
        session <- private$sessions[[session_id]]
        
        # Check session timeout (1 hour)
        if (difftime(Sys.time(), session$login_time, units = "hours") < 1) {
          return(list(valid = TRUE, user = session))
        }
      }
      
      return(list(valid = FALSE))
    },
    
    logout = function(session_id) {
      if (session_id %in% names(private$sessions)) {
        private$sessions[[session_id]] <- NULL
        return(TRUE)
      }
      return(FALSE)
    },
    
    has_permission = function(user, resource, action) {
      # Simple RBAC
      # Roles: admin > designer > viewer
      
      if (user$role == "admin") return(TRUE)
      
      if (user$role == "designer") {
        if (action %in% c("read", "write", "execute")) return(TRUE)
      }
      
      if (user$role == "viewer") {
        if (action == "read") return(TRUE)
      }
      
      return(FALSE)
    }
  )
)
