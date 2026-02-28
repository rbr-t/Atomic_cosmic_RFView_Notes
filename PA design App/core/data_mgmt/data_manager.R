# Data Manager - Core System
# Handles data import/export, transformation, and storage

library(R6)
library(DBI)
library(jsonlite)

DataManager <- R6Class("DataManager",
  private = list(
    db_pool = NULL,
    upload_dir = "data/uploads/",
    export_dir = "data/exports/"
  ),
  
  public = list(
    initialize = function(db_pool) {
      private$db_pool <- db_pool
      
      # Ensure directories exist
      if (!dir.exists(private$upload_dir)) dir.create(private$upload_dir, recursive = TRUE)
      if (!dir.exists(private$export_dir)) dir.create(private$export_dir, recursive = TRUE)
      
      self$init_schema()
    },
    
    init_schema = function() {
      query <- "
        CREATE TABLE IF NOT EXISTS datasets (
          id UUID PRIMARY KEY,
          project_id UUID REFERENCES projects(id),
          name VARCHAR(255) NOT NULL,
          type VARCHAR(50),
          format VARCHAR(20),
          file_path TEXT,
          metadata JSONB,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      "
      
      tryCatch({
        dbExecute(private$db_pool, query)
      }, error = function(e) {
        message("Note: Datasets table may already exist or DB not connected")
      })
    },
    
    import_data = function(file_path, project_id, type = "measurement", format = "csv") {
      # Import data from file
      data <- switch(format,
        "csv" = read.csv(file_path),
        "excel" = readxl::read_excel(file_path),
        "touchstone" = self$read_touchstone(file_path),
        stop("Unsupported format")
      )
      
      # Store in database
      dataset_id <- UUIDgenerate()
      
      # Save metadata
      metadata <- list(
        rows = nrow(data),
        cols = ncol(data),
        columns = colnames(data),
        import_time = Sys.time()
      )
      
      query <- "
        INSERT INTO datasets (id, project_id, name, type, format, file_path, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
      "
      
      tryCatch({
        dbExecute(
          private$db_pool,
          query,
          params = list(
            dataset_id, project_id, basename(file_path),
            type, format, file_path, toJSON(metadata)
          )
        )
      }, error = function(e) {
        message("Database insert failed, continuing with in-memory data")
      })
      
      return(list(
        id = dataset_id,
        data = data,
        metadata = metadata
      ))
    },
    
    export_data = function(data, filename, format = "csv") {
      export_path <- file.path(private$export_dir, filename)
      
      switch(format,
        "csv" = write.csv(data, export_path, row.names = FALSE),
        "json" = write(toJSON(data, pretty = TRUE), export_path),
        "rds" = saveRDS(data, export_path),
        stop("Unsupported format")
      )
      
      return(export_path)
    },
    
    read_touchstone = function(file_path) {
      # Simple Touchstone (S-parameter) file reader
      lines <- readLines(file_path)
      
      # Skip comments and header
      data_lines <- lines[!grepl("^[!#]", lines)]
      
      # Parse data (frequency, S11_mag, S11_phase, S21_mag, S21_phase, ...)
      data <- read.table(text = data_lines, header = FALSE)
      
      # Assign column names based on number of ports
      # For 2-port: freq, S11_real, S11_imag, S21_real, S21_imag, S12_real, S12_imag, S22_real, S22_imag
      colnames(data)[1] <- "frequency_hz"
      
      return(data)
    },
    
    validate_data = function(data, schema) {
      # Validate data against schema
      required_cols <- schema$required_columns
      
      missing_cols <- setdiff(required_cols, colnames(data))
      
      if (length(missing_cols) > 0) {
        return(list(
          valid = FALSE,
          errors = paste("Missing columns:", paste(missing_cols, collapse = ", "))
        ))
      }
      
      return(list(valid = TRUE, errors = NULL))
    },
    
    get_dataset = function(dataset_id) {
      query <- "SELECT * FROM datasets WHERE id = $1"
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query, params = list(dataset_id))
        return(result)
      }, error = function(e) {
        return(NULL)
      })
    },
    
    list_datasets = function(project_id = NULL) {
      if (is.null(project_id)) {
        query <- "SELECT * FROM datasets ORDER BY created_at DESC"
        params <- list()
      } else {
        query <- "SELECT * FROM datasets WHERE project_id = $1 ORDER BY created_at DESC"
        params <- list(project_id)
      }
      
      tryCatch({
        result <- dbGetQuery(private$db_pool, query, params = params)
        return(result)
      }, error = function(e) {
        return(data.frame())
      })
    }
  )
)
