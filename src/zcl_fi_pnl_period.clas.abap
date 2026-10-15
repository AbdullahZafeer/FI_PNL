"! <p class="shorttext synchronized">P&amp;L Report - Period Cutoff Determination</p>
"! FSD 7 requires this to be an isolated, independently testable unit,
"! separate from aggregation and roll-up. It answers exactly one question:
"!
"!   "Given a Reporting Year and an optional Reporting Date, which fiscal
"!    year am I reporting on, and which is the last period that shows
"!    actuals?"
"!
"! Everything after that period is forced to zero by the builder, whether
"! or not postings exist there.
CLASS zcl_fi_pnl_period DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_selection,
             fiscal_year      TYPE zif_fi_pnl_types=>ty_fiscal_year,
             prev_fiscal_year TYPE zif_fi_pnl_types=>ty_fiscal_year,
             " 1..12. Current-year periods greater than this are zeroed.
             last_period      TYPE i,
           END OF ty_selection.

    "! Determine the reporting year and the last period showing actuals.
    "! @parameter iv_company_code   | company code, e.g. 1000
    "! @parameter iv_reporting_year | mandatory unless a date is supplied
    "! @parameter iv_reporting_date | optional cutoff date
    "! At least one of the two must be supplied. If neither is, the
    "! returned fiscal year is 0 and the caller produces an empty report -
    "! Reporting Year is a mandatory selection field (FSD 7), so this is
    "! a caller error, not something to guess a default for.
    CLASS-METHODS determine_selection
      IMPORTING iv_company_code     TYPE zif_fi_pnl_types=>ty_company_code
                iv_reporting_year   TYPE zif_fi_pnl_types=>ty_fiscal_year OPTIONAL
                iv_reporting_date   TYPE zif_fi_pnl_types=>ty_date        OPTIONAL
      RETURNING VALUE(rs_selection) TYPE ty_selection.

    "! Fiscal year + period that a calendar date falls into, for the
    "! fiscal year variant assigned to the company code.
    "! Searle runs a July-June fiscal year, so 15.08.2025 is period 002
    "! of fiscal year 2025 - NOT period 008.
    CLASS-METHODS date_to_fiscal_period
      IMPORTING iv_company_code TYPE zif_fi_pnl_types=>ty_company_code
                iv_date         TYPE zif_fi_pnl_types=>ty_date
      EXPORTING ev_fiscal_year  TYPE zif_fi_pnl_types=>ty_fiscal_year
                ev_period       TYPE i.

ENDCLASS.


CLASS zcl_fi_pnl_period IMPLEMENTATION.

  METHOD determine_selection.

    " ----------------------------------------------------------------
    " Case 1: no Reporting Date -> full fiscal year.
    " All 12 periods are shown as currently posted, including periods
    " that are in the future relative to today.
    " [OPEN 2 in the FSD] - if the business later says "zero out future
    " periods here too", the only change needed is in this branch.
    " ----------------------------------------------------------------
    IF iv_reporting_date IS INITIAL.

      " No year either - nothing to report on. FISCAL_YEAR stays 0 and
      " the builder returns an empty result.
      IF iv_reporting_year IS INITIAL.
        RETURN.
      ENDIF.

      rs_selection-fiscal_year = iv_reporting_year.
      rs_selection-last_period = zif_fi_pnl_types=>gc_period_count.

    ELSE.

      " --------------------------------------------------------------
      " Case 2: Reporting Date supplied.
      " The fiscal year is DERIVED from the date (FSD 7), so the date
      " wins if both fields are filled. This is the direction chosen for
      " [OPEN 3]; changing it means changing these five lines only.
      " --------------------------------------------------------------
      date_to_fiscal_period(
        EXPORTING iv_company_code = iv_company_code
                  iv_date         = iv_reporting_date
        IMPORTING ev_fiscal_year  = rs_selection-fiscal_year
                  ev_period       = rs_selection-last_period ).

    ENDIF.

    " The date could not be resolved against the fiscal year variant
    " (unknown company code, or a date outside the calendar). Return an
    " empty selection rather than reporting on fiscal year 0000.
    IF rs_selection-fiscal_year IS INITIAL.
      CLEAR rs_selection.
      RETURN.
    ENDIF.

    " Guard rails: a period outside 1..12 would silently drop columns.
    IF rs_selection-last_period < 1 OR
       rs_selection-last_period > zif_fi_pnl_types=>gc_period_count.
      rs_selection-last_period = zif_fi_pnl_types=>gc_period_count.
    ENDIF.

    " Previous Year is always the full prior fiscal year, never cut off.
    rs_selection-prev_fiscal_year = rs_selection-fiscal_year - 1.

  ENDMETHOD.


  METHOD date_to_fiscal_period.

    CLEAR: ev_fiscal_year, ev_period.

    " Which fiscal year variant does this company code use?
    SELECT SINGLE FiscalYearVariant
      FROM I_CompanyCode
      WHERE CompanyCode = @iv_company_code
      INTO @DATA(lv_fyv).

    IF sy-subrc <> 0 OR lv_fyv IS INITIAL.
      RETURN.
    ENDIF.

    " I_FiscalCalendarDate maps every calendar date to the fiscal
    " year / period of a given variant. This is the one place in the
    " whole report that knows Searle's year starts in July.
    "
    " *** VERIFY IN ADT ***: open I_FiscalCalendarDate with Ctrl+Shift+A
    " and confirm the view and these three field names exist and are
    " released. If it is not available on your tenant, this method is
    " the only thing that has to change (FSD 7 / FSD 10).
    SELECT SINGLE FiscalYear, FiscalPeriod
      FROM I_FiscalCalendarDate
      WHERE FiscalYearVariant = @lv_fyv
        AND CalendarDate      = @iv_date
      INTO ( @ev_fiscal_year, @DATA(lv_period) ).

    IF sy-subrc = 0.
      ev_period = lv_period.
    ENDIF.

  ENDMETHOD.

ENDCLASS.

