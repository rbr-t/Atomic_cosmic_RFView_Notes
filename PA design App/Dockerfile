FROM rocker/shiny:4.3

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpq-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN R -e "install.packages(c( \
    'shiny', \
    'shinydashboard', \
    'shinyjs', \
    'plotly', \
    'DT', \
    'R6', \
    'yaml', \
    'DBI', \
    'pool', \
    'RPostgres', \
    'httr', \
    'jsonlite', \
    'readxl', \
    'uuid', \
    'duckdb' \
    ), repos='https://cloud.r-project.org/')"

# Create app directory
RUN mkdir -p /srv/shiny-server/pa-design-app

# Copy application files
COPY R /srv/shiny-server/pa-design-app/R
COPY core /srv/shiny-server/pa-design-app/core
COPY plugins /srv/shiny-server/pa-design-app/plugins
COPY config /srv/shiny-server/pa-design-app/config
COPY data /srv/shiny-server/pa-design-app/data

# Set working directory
WORKDIR /srv/shiny-server/pa-design-app

# Expose port
EXPOSE 3838

# Run app
CMD ["R", "-e", "shiny::runApp('R/app.R', host='0.0.0.0', port=3838)"]
