#' @title Create an Endemic Channel
#'
#' @description Exploratory Alarm Tool for Outbreak Detection.
#'
#' @describeIn epi_adapt_timeserie
#'
#' @param db_disease disease surveillance datasets
#' @param db_population estimated population for each adm area
#' @param var_admx administrative code r name as string
#' @param var_year year of agregated observations
#' @param var_week week of agregated observations
#' @param var_event_count number of events per week-year
#' @param var_population estimated population at that year
#'
#' @import dplyr
#' @import tidyr
#' @import broom
#' @import ggplot2
#'
#' @return canal endemico, union y grafico
#'
#' @export epi_adapt_timeserie
#' @export epi_create_channel
#' @export epi_join_channel
#' @export epi_plot_channel
#'
#' @examples
#'
#' library(tidyverse)
#'
#' # import data -------------------------------------------------------------
#'
#' dengv <-
#'   readr::read_csv("https://dengueforecasting.noaa.gov/Training/Iquitos_Training_Data.csv") %>%
#'   mutate(year = lubridate::year(week_start_date),
#'          epiweek = lubridate::epiweek(week_start_date)) %>%
#'   mutate(adm="iquitos") %>%
#'   # cases per season - replace wiht a dummy year
#'   mutate(year = str_replace(season,"(.+)/(.+)","\\1") %>% as.double())
#'
#' # dengv %>% count(year,season,lag_year)
#'
#' dengv %>% glimpse()
#'
#' # dengv %>%
#' #   ggplot(aes(x = week_start_date,y = total_cases)) +
#' #   geom_col()
#'
#' popdb <-
#'   readr::read_csv("https://dengueforecasting.noaa.gov/PopulationData/Iquitos_Population_Data.csv") %>%
#'   janitor::clean_names() %>%
#'   mutate(adm="iquitos")
#'
#' popdb %>% glimpse()
#'
#' # popdb %>% count(year)
#' # dengv %>% count(year)
#' # dengv %>% left_join(popdb)
#'
#' # first, adapt ------------------------------------------------------------
#'
#' epi_adapted <-
#'   epi_adapt_timeserie(db_disease = dengv,
#'                       db_population = popdb,
#'                       var_admx = adm,
#'                       # var_year = year, # must be a common variable between datasets
#'                       # var_week = epiweek,
#'                       var_year = year, # not working - need to create pseudo-years
#'                       var_week = season_week,
#'                       var_event_count = total_cases,
#'                       var_population = estimated_population)
#'
#' # second, filter ----------------------------------------------------------
#'
#' disease_now <- epi_adapted %>%
#'   filter(var_year==max(var_year))
#'
#' disease_pre <- epi_adapted %>%
#'   filter(var_year!=max(var_year))
#'
#' # third, create -----------------------------------------------------------
#'
#' disease_channel <-
#'   epi_create_channel(time_serie = disease_pre,
#'                      disease_name = "dengv")
#'
#' disease_channel
#'
#' # fourth, ggplot it -------------------------------------------------------
#'
#' epi_join_channel(disease_channel = disease_channel,
#'                  disease_now = disease_now) %>%
#'   # ggplot
#'   epi_plot_channel() +
#'   labs(title = "DENGV Endemic Channel. Iquitos, Peru 2008/2009",
#'        caption = "Source: https://dengueforecasting.noaa.gov/",
#'        # x = "epiweeks",
#'        x = "Seasonal week",
#'        y = "Number of cases") +
#'   theme_bw()
#'
#'

epi_adapt_timeserie <- function(db_disease,
                                db_population,
                                var_admx,
                                var_year,
                                var_week,
                                var_event_count,
                                var_population) {
  db_disease_f <- db_disease %>%
    #adapt variables
    rename(var_admx={{var_admx}},
           var_year={{var_year}},
           var_week={{var_week}},
           var_event_count={{var_event_count}})
  db_population_f <- db_population %>%
    #adapt variables
    rename(var_population={{var_population}},
           var_admx={{var_admx}},
           var_year={{var_year}})

  parte_1_4 <-
    #Paso 1:  N° de casos  por var_week,  7 años
    db_disease_f %>%
    # complete missings
    complete(var_admx,
             var_week=full_seq(var_week,1),
             var_year=full_seq(var_year,1),
             fill = list(var_event_count=0)) %>%
    #Paso 1.2: unir con el tamaño poplacional por var_admx-anho
    left_join(db_population_f) %>%

    ##Paso 1.3: retirar ubigeos sin poplacion para ningun anho
    ##naniar::miss_var_summary()
    ##filter(is.na(var_population)) %>% count(var_admx,var_year) %>% count(n)
    #filter(!is.na(var_population)) %>%

    #Paso 2: Cálculo de tasas y suma 1 (facilitar transformación en 0 casos)
    mutate(tasa=var_event_count/var_population*100000+1,
           #Paso 3: Transformación logarítmica de las tasas
           log_tasa=log(tasa))

  return(parte_1_4)
}

#' @describeIn epi_adapt_timeserie create endemic channel
#' @inheritParams epi_adapt_timeserie
#' @param time_serie time serie
#' @param disease_name free code name of diseases
#' @param method specify the method. "gmean_1sd" is geometric mean w/ 1 standard deviation (default). "gmean_2sd" is gmean w/ 2 sd. "gmean_ci" is gmean w/ 95 percent confidence intervals.

epi_create_channel <- function(time_serie,
                               disease_name="disease_name",
                               method="gmean_1sd") {

  parte_1_4 <- time_serie %>%
    #Paso 3: agrupar
    group_by(var_admx, var_week)

  db_population_f <- time_serie %>%
    select(var_admx,var_year,var_population) %>%
    distinct()

  if(method=="gmean_1sd"){
    parte_final <-
      parte_1_4 %>%
      # Paso 4: Cálculo de medias, 1*DE y delimitacion del 68.26% de valores del log_tasas
      summarise(media_l=mean(log_tasa), sd_l=sd(log_tasa)) %>%
      mutate(lo_95_l=media_l-(1*sd_l), hi_95_l=media_l+(1*sd_l)) %>%
      ungroup()
  }

  if(method=="gmean_2sd"){
    parte_final <-
      parte_1_4 %>%
      # Paso 4: Cálculo de medias, 2*DE y delimitacion del 95.48% de valores del log_tasas
      summarise(media_l=mean(log_tasa), sd_l=sd(log_tasa)) %>%
      mutate(lo_95_l=media_l-(2*sd_l), hi_95_l=media_l+(2*sd_l)) %>%
      ungroup()
  }

  if(method=="gmean_ci"){
    # Paso 4: Cálculo de median e IC95% de log_tasas
    parte_final <-
      parte_1_4 %>%
      nest() %>%
      #ungroup() %>% unnest(cols = c(data))
      # #ISSUE tagged -> non-vairability stops t.test
      # count(log_tasa,sort = T) %>%
      # ungroup() %>% filter(n==7) %>%
      # count(var_admx,sort = T)
      # count(log_tasa)
      # filter(is.na(log_tasa)) %>% count(var_admx)
      # #SOLUTION: retirar var_week con puro cero o NA
      # #PLAN 01
      mutate(sum_tasa=map_dbl(.x = data,.f = ~sum(.$log_tasa),na.rm=TRUE)) %>% #arrange(sum_tasa)
      filter(sum_tasa>0) %>%
      # mutate(t_test=map(.x = data,.f = ~t.test(.$log_tasa))) %>%
      # mutate(tidied=map(t_test,broom::tidy)) %>%
      # unnest(cols = c(tidied))
      # NOT WORKED: non-vairability  maintained after filter of values higher than 0
      #PLAN 02
      mutate(t_test=map(.x = data,.f = ~lm(log_tasa ~ 1,data=.x))) %>%
      mutate(tidied=map(t_test,broom::tidy),
             tidy_ci=map(t_test,broom::confint_tidy)) %>%
      unnest(cols = c(tidied,tidy_ci)) %>%
      rename(media_l=estimate,
             lo_95_l=conf.low,
             hi_95_l=conf.high) %>%
      ungroup()
  }


  parte_final %>%
    # Paso 5: Transformación a unidades originales (de log_tasas a tasas), menos 1 (agregado arriba)
    mutate(media_t= exp(media_l)-1, #sd_t= exp(sd_l)-1,
           lo_95_t=exp(lo_95_l)-1, hi_95_t=exp(hi_95_l)-1) %>%
    # Paso 6: Transformación a de tasas a casos (esperados)
    left_join(db_population_f %>%
                group_by(var_admx) %>%
                summarise(media_pop=mean(var_population))%>%
                ungroup()) %>%
    mutate(median=media_t*media_pop/100000,
           low_95=lo_95_t*media_pop/100000,
           upp_95=hi_95_t*media_pop/100000) %>%
    # seleccionado solo las variables a usar
    select(var_admx, var_week, median, low_95, upp_95) %>%
    mutate(key={{disease_name}})%>%
    mutate(var_admx=as.factor(var_admx)) %>%
    return()

}

#' @describeIn epi_adapt_timeserie join preliminary steps
#' @inheritParams epi_adapt_timeserie
#' @param disease_channel salida de epi_*_mutate
#' @param disease_now nueva base de vigilancia
#' @param adm_columns dataframe with names of the administrative code or name strings

epi_join_channel <- function(disease_channel,
                             disease_now,
                             adm_columns=NULL) {
  #unir con canal
  out <- disease_channel %>%
    full_join(disease_now)
  if (!is.null(adm_columns)) {
    out <- out %>%
      left_join(
        adm_columns
      ) #%>%
    # mutate_at(.vars = vars(value,low_95,upp_95,median),replace_na,0)
  }
  return(out)
}

#' @describeIn epi_adapt_timeserie create ggplot
#' @inheritParams epi_adapt_timeserie
#' @param joined_channel base de datos unida
#' @param n_breaks number of breaks in x axis

epi_plot_channel <- function(joined_channel,n_breaks=10) {
  #unir con canal
  # plot_name <- joined_channel %>%
  #   select(dist,prov,dpto) %>%
  #   distinct() %>% as.character() %>% paste(collapse = ", ")
  joined_channel %>%
    group_by(var_admx) %>%
    mutate(new= max(c(var_event_count,upp_95),na.rm = T),
           #plot_name= str_c(dist,"\n",prov,"\n",dpto)
    ) %>%
    ungroup() %>%
    ggplot(aes(x = var_week, y = var_event_count#, fill=key
    )) +
    geom_area(aes(x=var_week, y=new), fill = "#981000", alpha=0.6, stat="identity")+
    geom_area(aes(x=var_week, y=upp_95), fill = "#fee76a", stat="identity")+
    geom_area(aes(x=var_week, y=median), fill = "#3e9e39",  stat="identity")+
    geom_area(aes(x=var_week, y=low_95), fill = "white", stat="identity") +
    geom_line(size = 0.8) +
    scale_x_continuous(breaks = scales::pretty_breaks(n = {{n_breaks}})) #+
  # xlab("semanas") + ylab("N° de casos") #+
  #labs(title = paste0("Distrito de ",plot_name))
}

#' @describeIn epi_adapt_timeserie create ggplot
#' @inheritParams epi_adapt_timeserie

epi_observe_alert <- function(joined_channel,threshold=upp_95,alert_distance=3) {
  joined_channel %>%
    filter(var_event_count>{{threshold}}) %>%
    group_by(var_admx) %>%
    mutate(difference_lag=var_week-lag(var_week),
           difference_lead=lead(var_week)-var_week) %>%
    ungroup() %>%
    rowwise() %>%
    mutate(difference_min=min(c_across(difference_lag:difference_lead))) %>%
    ungroup() %>%
    select(-difference_lag,-difference_lead) %>%
    filter(difference_min<alert_distance)
}
