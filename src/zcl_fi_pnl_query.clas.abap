"! <p class="shorttext synchronized">P&amp;L Report - RAP Query Provider</p>
"! Entry point of the OData service. The framework calls SELECT once per
"! request; this class does three things and nothing else:
"!
"!   1. pull the selection values out of the OData $filter
"!   2. ask ZCL_FI_PNL_BUILDER for the complete report
"!   3. serve $count and the requested $skip / $top slice of it
"!
"! The full result is built once and then paged in memory (FSD 8). The
"! Excel export walks the same service page by page, so re-running the
"! whole aggregation per page would be wasteful.
"!
"! There is no TRY/CATCH here on purpose. Nothing below raises a checked
"! exception, and CX_RAP_QUERY_PROVIDER - the only exception SELECT is
"! allowed to raise - is abstract, so it cannot be raised directly. A
"! genuine runtime error therefore surfaces as a short dump, which is
"! what you want while developing: the dump names the failing statement.
CLASS zcl_fi_pnl_query DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PRIVATE SECTION.
    "! First LOW value of a filter, or an empty string if not supplied.
    "! Only single values are supported - the selection fields are single
    "! values by design, not ranges.
    METHODS filter_value
      IMPORTING it_ranges       TYPE if_rap_query_filter=>tt_name_range_pairs
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    "! Answer an empty result set without building anything.
    METHODS respond_empty
      IMPORTING io_request  TYPE REF TO if_rap_query_request
                io_response TYPE REF TO if_rap_query_response.

ENDCLASS.


CLASS zcl_fi_pnl_query IMPLEMENTATION.

  METHOD if_rap_query_provider~select.

    " ----------------------------------------------------------------
    " 1. read the selection out of the $filter
    " ----------------------------------------------------------------
    DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).

    DATA(lv_company_code) = CONV zif_fi_pnl_types=>ty_company_code(
      filter_value( it_ranges = lt_ranges iv_name = 'COMPANYCODE' ) ).

    DATA(lv_ledger) = CONV zif_fi_pnl_types=>ty_ledger(
      filter_value( it_ranges = lt_ranges iv_name = 'LEDGER' ) ).

    DATA(lv_year) = CONV zif_fi_pnl_types=>ty_fiscal_year(
      filter_value( it_ranges = lt_ranges iv_name = 'REPORTINGYEAR' ) ).

    DATA(lv_view) = CONV zif_fi_pnl_types=>ty_view(
      filter_value( it_ranges = lt_ranges iv_name = 'VIEWMODE' ) ).

    " A date filter arrives as a string. Depending on the client it is
    " either 20250815 or 2025-08-15, so normalise both forms.
    DATA(lv_date_string) = filter_value( it_ranges = lt_ranges
                                         iv_name   = 'REPORTINGDATE' ).
    REPLACE ALL OCCURRENCES OF '-' IN lv_date_string WITH ''.
    DATA lv_date TYPE zif_fi_pnl_types=>ty_date.
    IF strlen( lv_date_string ) = 8.
      lv_date = lv_date_string.
    ENDIF.

    " ----------------------------------------------------------------
    " Mandatory selection (FSD 7). Company code is needed for the chart
    " of accounts, the currency and the fiscal year variant; and there
    " has to be either a Reporting Year or a Reporting Date to derive
    " one from. Anything less and there is no report to build.
    " ----------------------------------------------------------------
    IF lv_company_code IS INITIAL
       OR ( lv_year IS INITIAL AND lv_date IS INITIAL ).
      respond_empty( io_request  = io_request
                     io_response = io_response ).
      RETURN.
    ENDIF.

    " ----------------------------------------------------------------
    " 2. build the whole report once
    " ----------------------------------------------------------------
    DATA(lo_builder) = NEW zcl_fi_pnl_builder(
      iv_company_code   = lv_company_code
      iv_ledger         = lv_ledger
      iv_reporting_year = lv_year
      iv_reporting_date = lv_date
      iv_view           = lv_view ).

    DATA(lt_all) = lo_builder->build( ).

    " ----------------------------------------------------------------
    " 3. serve $count and the requested page
    " ----------------------------------------------------------------
    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( lines( lt_all ) ).
    ENDIF.

    IF io_request->is_data_requested( ).

      DATA(lv_offset)    = io_request->get_paging( )->get_offset( ).
      DATA(lv_page_size) = io_request->get_paging( )->get_page_size( ).

      DATA lt_page TYPE zcl_fi_pnl_builder=>ty_rows.

      DATA(lv_from) = lv_offset + 1.
      IF lv_from < 1.
        lv_from = 1.
      ENDIF.

      " A page size of 0 or less means "no $top" - send everything from
      " the offset onwards.
      DATA(lv_to) = COND i( WHEN lv_page_size > 0
                            THEN lv_offset + lv_page_size
                            ELSE lines( lt_all ) ).
      IF lv_to > lines( lt_all ).
        lv_to = lines( lt_all ).
      ENDIF.

      IF lv_to >= lv_from.
        LOOP AT lt_all INTO DATA(ls_row) FROM lv_from TO lv_to.
          APPEND ls_row TO lt_page.
        ENDLOOP.
      ENDIF.

      io_response->set_data( lt_page ).

    ENDIF.

    " NOTE: $orderby is deliberately ignored. The row sequence IS the
    " report - re-sorting it would put subtotals above their own detail
    " rows. The UI5 table must not offer column sorting.

  ENDMETHOD.


  METHOD respond_empty.

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( 0 ).
    ENDIF.

    IF io_request->is_data_requested( ).
      io_response->set_data( VALUE zcl_fi_pnl_builder=>ty_rows( ) ).
    ENDIF.

  ENDMETHOD.


  METHOD filter_value.

    LOOP AT it_ranges INTO DATA(ls_pair).
      IF to_upper( ls_pair-name ) = iv_name.
        IF ls_pair-range IS NOT INITIAL.
          rv_value = ls_pair-range[ 1 ]-low.
        ENDIF.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

