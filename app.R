library(shiny)
library(visNetwork)
library(tidyverse)
library(ggplot2)
library(useful)
library(assertthat)
library(lubridate)
library(RJSONIO)
library(parallel)

#source("app-only-auth-twitter.R")
source("src/floor.R")
source("src/wall.R")
source("src/network.R")
source("src/external-monitor.R")
source("src/utilities.R")
source("src/campfire_lib.R")

campfireApp(
  
  controller = div(
    h1("Controller"),
    fileInput("json_file", "JSON Input", accept = c("application/json")),
    textAreaInput("text_input",
                  "JSON Text",
                  value = read_file("test/test_ALLGROUPS_new.json"),
                  height = '455px',
                  width = "550px"),
    selectInput("rdata_file",
                "RDATA File", 
                choices = list.files("/data/BLM/TTimeMachinePeriods"),
                selected = "period_5_5.df.Rdata"),
    actionButton(inputId = "update",
                 label = "Update"),
    downloadButton("download", "Download JSON"),
    actionButton(inputId = "destroy",
                 label = "DESTROY"),
    style = "position: absolute; 
    top: 50%; left: 50%; 
    margin-right: -50%; 
    transform: translate(-50%, -50%)"
  ),
  
  wall = div(
    uiOutput("wall_ui"),
    style = paste0("background: ", color.back, "; overflow: hidden;",
                   "height: 665px")
  ),
  
  floor = div(
    visNetworkOutput("network", width = "1000px", height = "1000px"),
    style = paste0("position: absolute; 
           top: 50%; left: 50%;
           margin-right: -50%; 
           transform: translate(-50%, -50%);
           background: ", color.back,
           "; height: 1000px; overflow: hidden")
  ),
  
  datamonitor = div(fluidPage(
    fluidRow(
      column(12,
            uiOutput("tweets_info")
      )
    )),
    fluidRow(
      column(6,
             plotOutput("top.users.bar.extern", height = "920px")
             ),
      column(6,
             plotOutput("tweets.by.time", height = "920px")
             )
    ),
    style = paste0("background: ", color.back, ";
                   overflow: hidden;
                   height: 1080px")
  ),
  
  urlmonitor = div(fluidPage(
    htmlOutput("frame")
  )),
  
  serverFunct = function(ServerValues, output, session) {
    
    # Update text box when JSON file changes.
    observeEvent(ServerValues$parsed_json, {
      if(!is.null(ServerValues$parsed_json))
      {
        text <- toJSON(ServerValues$parsed_json, pretty = TRUE)
        ServerValues$text_input <- text
        updateTextInput(session, "text_input", value = text)
      }
    })
    
    output$download <- downloadHandler(
      filename = "ttm_output.json",
      content = function(file) {
        write(ServerValues$text_input, file)
      },
      contentType = "application/json"
    )
    
    output$wall_ui <- renderUI({
      fluidPage(
        tags$script(HTML(
          "$(document).on('click', '.clickable', function (event) {
            var text =  $(this).text();
            if(event.ctrlKey) {
              Shiny.onInputChange('open_url', true)
            } else {
              Shiny.onInputChange('open_url', false)
            }
            Shiny.onInputChange('clicked_text', text);
          });"
        )),
        fluidRow(
          lapply(1:12, function(col.num) {
            ServerValues$col_list[[col.num]]
          })
        )
      )
    })

    # render the floor
    output$network <- renderVisNetwork({
      if (!is.null(ServerValues$network)) {
        ServerValues$network %>%
            visEvents(type = "once", beforeDrawing = "function() {
              this.moveTo({
                            position: {
                              x: 0,
                              y: 0
                            },
                      scale: 1
              })
            }") %>%
            visEvents(
                      doubleClick = "function() {
                                       if(this.getSelectedNodes().length == 1) {
                                         Shiny.onInputChange('delete_node', this.getSelectedNodes()[0]);
                                         this.deleteSelected();
                                         Shiny.onInputChange('current_node_id', -1);
                                         Shiny.onInputChange('current_edge_index', -1);
                                       }
                                     }"
                    )
            }
        }
    )
    
    output$tweets_info <- renderUI(
    {
      if(ServerValues$network_selected != "")
      {
        node_info <- ServerValues$nodes[ServerValues$nodes$id == ServerValues$network_selected, ]
        node_info <- node_info[!is.na(node_info), ]
        node_size <- node_info$value
        node_name <- node_info$name
        tags$div(
          tags$h1(style = paste0("color:", color.blue), node_name),
          tags$h2(style = paste0("color:", color.blue), paste("Size:", node_size)))
      }
      else if(ServerValues$network_selected_e != "")
      {
        edge_data <- ServerValues$edges[ServerValues$network_selected_e, ]
        to_node_name <- ServerValues$nodes$name[ServerValues$nodes$id == edge_data$to]
        to_node_name <- to_node_name[!is.na(to_node_name)]
        from_node_name <- ServerValues$nodes$name[ServerValues$nodes$id == edge_data$from]
        from_node_name <- from_node_name[!is.na(from_node_name)]
        edge_name <- paste(to_node_name, "AND", from_node_name)
        edge_size <- edge_data$value
        tags$div(
          tags$h1(style = paste0("color:", color.blue), edge_name),
          tags$h2(style = paste0("color:", color.blue), paste("Type:", edge_data$colname)),
          tags$h2(style = paste0("color:", color.blue), paste("Size:", edge_size)))
      }
      else
      {
        tags$div(
          tags$h1(style = paste0("color:", color.blue), "Twitter Time Machine"),
          tags$h2(style = paste0("color:", color.blue), paste("Total number of tweets:", nrow(ServerValues$data))),
          tags$h2(style = paste0("color:", color.blue), paste("Data:", isolate(ServerValues$parsed_json$data_file)))
        )      
      }
    })
    
    output$top.users.bar.extern <- renderPlot({
      ServerValues$monitor.domain <- getDefaultReactiveDomain()
      ServerValues$data_subset %>%
        count(user_screen_name) %>%
        arrange(desc(n)) %>%
        slice(1:10) %>%
        ggplot(aes(reorder(user_screen_name, n), n)) +
        geom_col(fill = color.blue, color = color.blue) +
        coord_flip() +
        labs(x = "Screen Name", y = "Tweets", title = "Top 10 Users") +
        theme_dark() +
        theme(plot.background = element_rect(fill = color.back, color = NA),
              axis.text = element_text(size = 20, colour = color.white),
              text = element_text(size = 20, colour = color.blue))
    })
    
    output$tweets.by.time <- renderPlot({
      ServerValues$data_subset %>%
        group_by(group) %>%
        mutate(date = date(as_datetime(created_at))) %>%
        count(date) %>%
        ggplot(aes(x = date, y = n, group = group)) +
        scale_color_brewer(palette = "Spectral") + 
        geom_line(aes(color = factor(group)), size = 2) +
        labs(x = "Date", y = "Number of Tweets", title = "Tweets vs. Time", color = "Group") +
        theme_dark() +
        theme(plot.background = element_rect(fill = color.back, color = NA),
              axis.text = element_text(size = 20, colour = color.white),
              text = element_text(size = 20, colour = color.blue),
              legend.background = element_rect(fill = color.back))
    })

    output$frame <- renderUI({
      if(!is.null(ServerValues$url)) {
        redirectScript <- paste0("window = window.open('", ServerValues$url, "');")
        tags$script(HTML(redirectScript))
      } else {
        redirectScript <- paste0("window = window.open('", "https://docs.google.com/presentation/d/1g_q5qQTJAt4jVekozFlEsnEo4XdveubVzLC2t9aeWlo/present", "');")
        tags$script(HTML(redirectScript))
      }
    })
    
  }
)
