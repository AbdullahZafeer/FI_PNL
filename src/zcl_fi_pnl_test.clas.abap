"! <p class="shorttext synchronized">P&amp;L Report - Console Test Harness</p>
"! Run with F9. Does the whole README test sequence from inside ADT,
"! without any UI, and prints the report in the order it will be shown.
"!
"! Change the constants below to change the selection. This is the
"! fastest way to test: no service binding, no browser, no UI5 build.
CLASS zcl_fi_pnl_test DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    " ---------------- change these to test ----------------
    CONSTANTS gc_company_code TYPE zif_fi_pnl_types=>ty_company_code VALUE '1000'.
    CONSTANTS gc_ledger       TYPE zif_fi_pnl_types=>ty_ledger       VALUE '0L'.
    CONSTANTS gc_year         TYPE zif_fi_pnl_types=>ty_fiscal_year  VALUE '2027'.
    " Leave as all zeros for a full year, or set e.g. '20250915' to test
    " the cutoff. Periods after the one containing that date must be 0.
    CONSTANTS gc_date         TYPE zif_fi_pnl_types=>ty_date         VALUE '00000000'.
    " 'S' summary (node rows only) or 'D' detailed (with G/L rows)
    CONSTANTS gc_view         TYPE zif_fi_pnl_types=>ty_view         VALUE 'S'.

    " Step 6 breaks one node down account by account. COGS is the usual
    " suspect because three functional areas feed it.
    CONSTANTS gc_explain_node TYPE zif_fi_pnl_types=>ty_node_id      VALUE 'COGS'.
    CONSTANTS gc_explain_top  TYPE i                                 VALUE 25.

    TYPES: BEGIN OF ty_detail,
             gl_account TYPE zif_fi_pnl_types=>ty_gl_account,
             gl_type    TYPE c LENGTH 1,
             func_area  TYPE zif_fi_pnl_types=>ty_func_area,
             gl_name    TYPE c LENGTH 50,
             prev_year  TYPE zif_fi_pnl_types=>ty_amount,
             curr_year  TYPE zif_fi_pnl_types=>ty_amount,
             magnitude  TYPE zif_fi_pnl_types=>ty_amount,
           END OF ty_detail.
    TYPES ty_detail_t TYPE STANDARD TABLE OF ty_detail WITH EMPTY KEY.

    TYPES: BEGIN OF ty_type_sum,
             gl_type   TYPE c LENGTH 1,
             accounts  TYPE i,
             prev_year TYPE zif_fi_pnl_types=>ty_amount,
             curr_year TYPE zif_fi_pnl_types=>ty_amount,
           END OF ty_type_sum.
    TYPES ty_type_sum_t TYPE SORTED TABLE OF ty_type_sum WITH UNIQUE KEY gl_type.

    " Open SQL does not allow FOR ALL ENTRIES together with aggregate
    " functions and GROUP BY. Ranges have no such restriction, so the
    " SUM stays in the database instead of pulling raw line items.
    TYPES ty_farea_range  TYPE RANGE OF zif_fi_pnl_types=>ty_func_area.
    TYPES ty_glacct_range TYPE RANGE OF zif_fi_pnl_types=>ty_gl_account.

    DATA mo_out   TYPE REF TO if_oo_adt_classrun_out.
    DATA mv_coa   TYPE c LENGTH 4.
    DATA mv_prev  TYPE zif_fi_pnl_types=>ty_fiscal_year.
    " Control totals: every P&L posting in periods 001-012, whatever the
    " mapping does with it. Profit for the Year must equal these.
    DATA mv_ctl_prev TYPE zif_fi_pnl_types=>ty_amount.
    DATA mv_ctl_curr TYPE zif_fi_pnl_types=>ty_amount.
    " Set when the ledger read found nothing, so the checks in step 5
    " do not report "OK" for a comparison of 0.00 against 0.00.
    DATA mv_no_data  TYPE abap_bool.

    METHODS check_config  RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS check_company RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS check_ledger_data.
    METHODS print_report.
    METHODS explain_node.
    METHODS explain_unassigned.
    METHODS type_text IMPORTING iv_type        TYPE c
                      RETURNING VALUE(rv_text) TYPE string.
    METHODS line IMPORTING iv_text TYPE string.

ENDCLASS.


CLASS zcl_fi_pnl_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    mo_out  = out.
    mv_prev = gc_year - 1.

    line( |=== P&L report test =============================================| ).
    line( |company code { gc_company_code }  ledger { gc_ledger }  year { gc_year }  | &&
          |date { gc_date }  view { gc_view }| ).
    line( || ).

    IF check_config( ) = abap_false.
      RETURN.
    ENDIF.

    IF check_company( ) = abap_false.
      RETURN.
    ENDIF.

    check_ledger_data( ).
    print_report( ).
    explain_node( ).
    explain_unassigned( ).

  ENDMETHOD.


  METHOD check_config.

    SELECT COUNT(*) FROM zfi_pnl_node   INTO @DATA(lv_nodes).
    SELECT COUNT(*) FROM zfi_pnl_child  INTO @DATA(lv_children).
    SELECT COUNT(*) FROM zfi_pnl_farea  INTO @DATA(lv_areas).
    SELECT COUNT(*) FROM zfi_pnl_gllist INTO @DATA(lv_accounts).

    line( |--- 1. customizing ----------------------------------------------| ).
    line( |ZFI_PNL_NODE   { lv_nodes     } (expected 21)| ).
    line( |ZFI_PNL_CHILD  { lv_children  } (expected 20)| ).
    line( |ZFI_PNL_FAREA  { lv_areas     } (expected 12)| ).
    line( |ZFI_PNL_GLLIST { lv_accounts  } (expected 26)| ).

    IF lv_nodes = 0.
      line( || ).
      line( |STOP: no customizing. Run ZCL_FI_PNL_SETUP with F9.| ).
      RETURN.
    ENDIF.

    SELECT SINGLE gl_account FROM zfi_pnl_gllist INTO @DATA(lv_sample).
    line( |sample stored G/L account: "{ lv_sample }"| ).

    line( || ).
    rv_ok = abap_true.

  ENDMETHOD.


  METHOD check_company.

    line( |--- 2. company code ---------------------------------------------| ).

    SELECT SINGLE ChartOfAccounts, Currency, FiscalYearVariant
      FROM I_CompanyCode
      WHERE CompanyCode = @gc_company_code
      INTO @DATA(ls_cc).

    IF sy-subrc <> 0.
      line( |STOP: company code { gc_company_code } not found.| ).
      RETURN.
    ENDIF.

    mv_coa = ls_cc-ChartOfAccounts.

    line( |chart of accounts   { ls_cc-ChartOfAccounts }| ).
    line( |currency            { ls_cc-Currency }| ).
    line( |fiscal year variant { ls_cc-FiscalYearVariant }| ).
    line( || ).
    rv_ok = abap_true.

  ENDMETHOD.


  METHOD check_ledger_data.

    line( |--- 3. raw ledger data ------------------------------------------| ).

    SELECT FROM I_JournalEntryItem
      FIELDS FiscalYear                         AS fiscal_year,
             COUNT(*)                           AS items,
             SUM( AmountInCompanyCodeCurrency ) AS total
      WHERE CompanyCode = @gc_company_code
        AND Ledger      = @gc_ledger
        AND FiscalYear  IN ( @gc_year, @mv_prev )
      GROUP BY FiscalYear
      ORDER BY FiscalYear
      INTO TABLE @DATA(lt_raw).

    IF lt_raw IS INITIAL.

      " ------------------------------------------------------------
      " Nothing at all - not "nothing in the P&L", nothing in the
      " ledger. This query has no join, no account type filter and no
      " mapping, so an empty result means the company code, the ledger,
      " the fiscal years or the CLIENT is not what you think it is.
      " The probe below shows what actually exists, so you can see at a
      " glance which of the four is wrong.
      " ------------------------------------------------------------
      line( |NO POSTINGS AT ALL for company code { gc_company_code }, | &&
            |ledger { gc_ledger }, fiscal years { mv_prev } / { gc_year }.| ).
      line( || ).
      line( |what this client actually contains:| ).

      SELECT FROM I_JournalEntryItem
        FIELDS CompanyCode AS company_code,
               Ledger      AS ledger,
               FiscalYear  AS fiscal_year,
               COUNT(*)    AS items
        GROUP BY CompanyCode, Ledger, FiscalYear
        ORDER BY CompanyCode, Ledger, FiscalYear
        INTO TABLE @DATA(lt_probe)
        UP TO 60 ROWS.

      IF lt_probe IS INITIAL.
        line( |  nothing at all - this client has no journal entries.| ).
      ELSE.
        line( |  CoCd Ledger FY     Items| ).
        LOOP AT lt_probe INTO DATA(ls_probe).
          line( |  { ls_probe-company_code } { ls_probe-ledger WIDTH = 6 } | &&
                |{ ls_probe-fiscal_year } { ls_probe-items WIDTH = 9 ALIGN = RIGHT }| ).
        ENDLOOP.
      ENDIF.

      line( || ).
      mv_no_data = abap_true.
      RETURN.

    ENDIF.

    LOOP AT lt_raw INTO DATA(ls_raw).
      line( |FY { ls_raw-fiscal_year }: { ls_raw-items } items, | &&
            |all accounts total { ls_raw-total } (0.00 = balanced ledger, expected)| ).
    ENDLOOP.

    " ----------------------------------------------------------------
    " The control total. This is every P&L posting in periods 001-012,
    " regardless of what the mapping does with it, so Profit for the
    " Year must equal it exactly. That is acceptance criterion 1, and
    " it is checked automatically in step 5.
    " ----------------------------------------------------------------
    SELECT FROM I_JournalEntryItem AS je
      INNER JOIN I_GLAccountInChartOfAccounts AS gl
              ON  gl~ChartOfAccounts = @mv_coa
              AND gl~GLAccount       = je~GLAccount
      FIELDS je~FiscalYear                            AS fiscal_year,
             gl~GLAccountType                         AS gl_type,
             COUNT(*)                                 AS items,
             SUM( je~AmountInCompanyCodeCurrency )    AS total
      WHERE je~CompanyCode   = @gc_company_code
        AND je~Ledger        = @gc_ledger
        AND je~FiscalYear    IN ( @gc_year, @mv_prev )
        AND je~FiscalPeriod  BETWEEN '001' AND '012'
      GROUP BY je~FiscalYear, gl~GLAccountType
      ORDER BY je~FiscalYear, gl~GLAccountType
      INTO TABLE @DATA(lt_by_type).

    line( || ).
    line( |postings by G/L account type, periods 001-012:| ).
    LOOP AT lt_by_type INTO DATA(ls_type).
      line( |FY { ls_type-fiscal_year } type { ls_type-gl_type } | &&
            |{ type_text( ls_type-gl_type ) WIDTH = 34 } | &&
            |{ ls_type-items WIDTH = 8 ALIGN = RIGHT } items | &&
            |{ ls_type-total WIDTH = 22 ALIGN = RIGHT }| ).

      " N, P and S are the P&L types the report reads.
      IF ls_type-gl_type CA 'NPS'.
        IF ls_type-fiscal_year = gc_year.
          mv_ctl_curr = mv_ctl_curr + ls_type-total.
        ELSE.
          mv_ctl_prev = mv_ctl_prev + ls_type-total.
        ENDIF.
      ENDIF.
    ENDLOOP.

    line( || ).
    line( |P&L control total FY { mv_prev }: { mv_ctl_prev }| ).
    line( |P&L control total FY { gc_year }: { mv_ctl_curr }| ).
    line( || ).

  ENDMETHOD.


  METHOD print_report.

    line( |--- 4. the report -----------------------------------------------| ).

    DATA(lo_builder) = NEW zcl_fi_pnl_builder(
      iv_company_code   = gc_company_code
      iv_ledger         = gc_ledger
      iv_reporting_year = gc_year
      iv_reporting_date = gc_date
      iv_view           = gc_view ).

    DATA(lt_rows) = lo_builder->build( ).

    line( |{ lines( lt_rows ) } rows| ).
    line( || ).
    line( |T No.   Description                             G/L account | &&
          |      Previous Year       Current Year| ).
    line( |----------------------------------------------------------| &&
          |-------------------------------------| ).

    LOOP AT lt_rows INTO DATA(ls_row).
      DATA(lv_indent) = repeat( val = ` ` occ = ls_row-nodelevel * 2 ).
      line( |{ ls_row-rowtype } | &&
            |{ ls_row-displayno WIDTH = 5 } | &&
            |{ lv_indent }{ ls_row-description WIDTH = 40 } | &&
            |{ ls_row-glaccount WIDTH = 11 } | &&
            |{ ls_row-amountpreviousyear WIDTH = 18 ALIGN = RIGHT } | &&
            |{ ls_row-amountcurrentyear  WIDTH = 18 ALIGN = RIGHT }| ).
    ENDLOOP.

    line( || ).
    line( |--- 5. checks ---------------------------------------------------| ).

    " ---- acceptance criterion 1: reconcile to the ledger ----
    LOOP AT lt_rows INTO ls_row WHERE nodeid = 'PFY'.
      DATA(lv_diff_prev) = ls_row-amountpreviousyear - mv_ctl_prev.
      DATA(lv_diff_curr) = ls_row-amountcurrentyear  - mv_ctl_curr.
      line( |Profit for the Year vs ledger control total:| ).
      line( |  FY { mv_prev }: report { ls_row-amountpreviousyear } | &&
            |ledger { mv_ctl_prev } difference { lv_diff_prev }| ).
      line( |  FY { gc_year }: report { ls_row-amountcurrentyear } | &&
            |ledger { mv_ctl_curr } difference { lv_diff_curr }| ).
      IF mv_no_data = abap_true.
        line( |  NOT A TEST - there were no postings to reconcile.| ).
        line( |  0.00 = 0.00 proves nothing. Fix the selection first.| ).
      ELSEIF lv_diff_prev = 0 AND lv_diff_curr = 0.
        line( |  OK - the report accounts for every P&L posting.| ).
      ELSE.
        line( |  MISMATCH - postings are being lost or double counted.| ).
      ENDIF.
    ENDLOOP.

    " ---- the reconciliation line ----
    LOOP AT lt_rows INTO ls_row
         WHERE nodeid = zif_fi_pnl_types=>gc_unassigned_node.
      line( |Unassigned: prev { ls_row-amountpreviousyear } | &&
            |curr { ls_row-amountcurrentyear }| ).
    ENDLOOP.

    " ---- period columns vs Current Year ----
    DATA(lv_bad) = 0.
    LOOP AT lt_rows INTO ls_row.
      DATA(lv_sum) = CONV zif_fi_pnl_types=>ty_amount( 0 ).
      DO zif_fi_pnl_types=>gc_period_count TIMES.
        ASSIGN COMPONENT
          |AMOUNTPERIOD{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
          OF STRUCTURE ls_row TO FIELD-SYMBOL(<lv_period>).
        IF sy-subrc = 0.
          lv_sum = lv_sum + <lv_period>.
        ENDIF.
      ENDDO.
      IF lv_sum <> ls_row-amountcurrentyear.
        lv_bad = lv_bad + 1.
      ENDIF.
    ENDLOOP.
    line( |period columns vs Current Year: { lv_bad } mismatches (must be 0)| ).
    line( || ).

  ENDMETHOD.


  METHOD explain_node.

    line( |--- 6. what is actually inside node { gc_explain_node } ---------------------| ).

    SELECT func_area FROM zfi_pnl_farea
      WHERE node_id = @gc_explain_node
      INTO TABLE @DATA(lt_areas).

    IF lt_areas IS INITIAL.
      line( |node { gc_explain_node } is not fed by functional area.| ).
      line( |(for the reconciliation line use step 7 instead)| ).
      RETURN.
    ENDIF.

    DATA(lr_areas) = VALUE ty_farea_range(
      FOR ls_area IN lt_areas ( sign = 'I' option = 'EQ' low = ls_area-func_area ) ).

    " ----------------------------------------------------------------
    " Deliberately NOT filtered by G/L account type, unlike the report.
    " If balance sheet accounts (type X) or cash accounts (type C) show
    " up here, they are being posted with a functional area that this
    " node claims - a master data problem, not a report problem.
    " ----------------------------------------------------------------
    SELECT FROM I_JournalEntryItem AS je
      INNER JOIN I_GLAccountInChartOfAccounts AS gl
              ON  gl~ChartOfAccounts = @mv_coa
              AND gl~GLAccount       = je~GLAccount
      FIELDS je~GLAccount                         AS gl_account,
             gl~GLAccountType                     AS gl_type,
             je~FunctionalArea                    AS func_area,
             je~FiscalYear                        AS fiscal_year,
             SUM( je~AmountInCompanyCodeCurrency ) AS amount
      WHERE je~CompanyCode    = @gc_company_code
        AND je~Ledger         = @gc_ledger
        AND je~FiscalYear     IN ( @gc_year, @mv_prev )
        AND je~FiscalPeriod   BETWEEN '001' AND '012'
        AND je~FunctionalArea IN @lr_areas
      GROUP BY je~GLAccount, gl~GLAccountType, je~FunctionalArea, je~FiscalYear
      INTO TABLE @DATA(lt_raw).

    IF lt_raw IS INITIAL.
      line( |no postings on these functional areas.| ).
      RETURN.
    ENDIF.

    " pivot the two fiscal years onto one line per account
    DATA lt_detail TYPE ty_detail_t.
    LOOP AT lt_raw INTO DATA(ls_raw).
      READ TABLE lt_detail ASSIGNING FIELD-SYMBOL(<ls_det>)
           WITH KEY gl_account = ls_raw-gl_account
                    func_area  = ls_raw-func_area.
      IF sy-subrc <> 0.
        " ASSIGNING is only allowed on APPEND INITIAL LINE, not on
        " APPEND <work area>.
        APPEND INITIAL LINE TO lt_detail ASSIGNING <ls_det>.
        <ls_det>-gl_account = ls_raw-gl_account.
        <ls_det>-gl_type    = ls_raw-gl_type.
        <ls_det>-func_area  = ls_raw-func_area.
      ENDIF.
      IF ls_raw-fiscal_year = gc_year.
        <ls_det>-curr_year = <ls_det>-curr_year + ls_raw-amount.
      ELSE.
        <ls_det>-prev_year = <ls_det>-prev_year + ls_raw-amount.
      ENDIF.
    ENDLOOP.

    " account names
    SELECT FROM I_GLAccountText
      FIELDS GLAccount AS gl_account, GLAccountLongName AS gl_name
      FOR ALL ENTRIES IN @lt_detail
      WHERE ChartOfAccounts = @mv_coa
        AND GLAccount       = @lt_detail-gl_account
        AND Language        = @sy-langu
      INTO TABLE @DATA(lt_text).

    LOOP AT lt_detail ASSIGNING <ls_det>.
      READ TABLE lt_text INTO DATA(ls_text)
           WITH KEY gl_account = <ls_det>-gl_account.
      IF sy-subrc = 0.
        <ls_det>-gl_name = ls_text-gl_name.
      ENDIF.
      <ls_det>-magnitude = abs( <ls_det>-curr_year ) + abs( <ls_det>-prev_year ).
    ENDLOOP.

    " ---- summary by account type: the answer is usually here ----
    DATA lt_by_type TYPE ty_type_sum_t.
    LOOP AT lt_detail INTO DATA(ls_det).
      READ TABLE lt_by_type ASSIGNING FIELD-SYMBOL(<ls_sum>)
           WITH TABLE KEY gl_type = ls_det-gl_type.
      IF sy-subrc <> 0.
        DATA ls_new TYPE ty_type_sum.
        CLEAR ls_new.
        ls_new-gl_type = ls_det-gl_type.
        INSERT ls_new INTO TABLE lt_by_type ASSIGNING <ls_sum>.
      ENDIF.
      <ls_sum>-accounts  = <ls_sum>-accounts + 1.
      <ls_sum>-prev_year = <ls_sum>-prev_year + ls_det-prev_year.
      <ls_sum>-curr_year = <ls_sum>-curr_year + ls_det-curr_year.
    ENDLOOP.

    line( || ).
    line( |by G/L account type:| ).
    LOOP AT lt_by_type INTO DATA(ls_sum).
      line( |  type { ls_sum-gl_type } { type_text( ls_sum-gl_type ) WIDTH = 34 } | &&
            |{ ls_sum-accounts WIDTH = 5 ALIGN = RIGHT } accounts | &&
            |prev { ls_sum-prev_year WIDTH = 20 ALIGN = RIGHT } | &&
            |curr { ls_sum-curr_year WIDTH = 20 ALIGN = RIGHT }| ).
    ENDLOOP.

    " ---- the biggest accounts ----
    SORT lt_detail BY magnitude DESCENDING.
    line( || ).
    line( |top { gc_explain_top } accounts by size:| ).
    line( |Ty FArea  G/L account Name                              | &&
          |       Previous Year        Current Year| ).
    line( |----------------------------------------------------------| &&
          |------------------------------------------| ).

    LOOP AT lt_detail INTO ls_det FROM 1 TO gc_explain_top.
      line( |{ ls_det-gl_type } { ls_det-func_area WIDTH = 6 } | &&
            |{ ls_det-gl_account } { ls_det-gl_name WIDTH = 34 } | &&
            |{ ls_det-prev_year WIDTH = 19 ALIGN = RIGHT } | &&
            |{ ls_det-curr_year WIDTH = 19 ALIGN = RIGHT }| ).
    ENDLOOP.

    line( || ).
    line( |{ lines( lt_detail ) } accounts in total on these functional areas.| ).

  ENDMETHOD.


  METHOD explain_unassigned.

    line( || ).
    line( |--- 7. what is in the Unassigned line ---------------------------| ).

    " A posting lands in Unassigned when its G/L account is not in
    " Annex A AND its functional area is not mapped to any node. This
    " lists exactly which functional areas those are - which is the
    " evidence the functional team needs for FSD open item 1.
    SELECT func_area FROM zfi_pnl_farea INTO TABLE @DATA(lt_mapped).
    SELECT gl_account FROM zfi_pnl_gllist INTO TABLE @DATA(lt_annex).

    IF lt_mapped IS INITIAL OR lt_annex IS INITIAL.
      line( |customizing incomplete - cannot analyse.| ).
      RETURN.
    ENDIF.

    DATA(lr_mapped) = VALUE ty_farea_range(
      FOR ls_m IN lt_mapped ( sign = 'I' option = 'EQ' low = ls_m-func_area ) ).
    DATA(lr_annex) = VALUE ty_glacct_range(
      FOR ls_a IN lt_annex ( sign = 'I' option = 'EQ' low = ls_a-gl_account ) ).

    SELECT FROM I_JournalEntryItem AS je
      INNER JOIN I_GLAccountInChartOfAccounts AS gl
              ON  gl~ChartOfAccounts = @mv_coa
              AND gl~GLAccount       = je~GLAccount
      FIELDS je~FunctionalArea                     AS func_area,
             je~FiscalYear                         AS fiscal_year,
             COUNT(*)                              AS items,
             SUM( je~AmountInCompanyCodeCurrency )  AS amount
      WHERE je~CompanyCode     = @gc_company_code
        AND je~Ledger          = @gc_ledger
        AND je~FiscalYear      IN ( @gc_year, @mv_prev )
        AND je~FiscalPeriod    BETWEEN '001' AND '012'
        AND gl~GLAccountType   IN ( 'N', 'P', 'S' )
        AND je~FunctionalArea  NOT IN @lr_mapped
        AND je~GLAccount       NOT IN @lr_annex
      GROUP BY je~FunctionalArea, je~FiscalYear
      ORDER BY je~FunctionalArea, je~FiscalYear
      INTO TABLE @DATA(lt_un).

    IF lt_un IS INITIAL.
      line( |nothing unassigned - every P&L posting has a home.| ).
      RETURN.
    ENDIF.

    SELECT FROM I_FunctionalAreaText
      FIELDS FunctionalArea AS func_area, FunctionalAreaName AS name
      WHERE Language = @sy-langu
      INTO TABLE @DATA(lt_fa_text).

    line( |FArea  Name                       FY     | &&
          |   Items               Amount| ).
    line( |--------------------------------------------------| &&
          |------------------------| ).

    LOOP AT lt_un INTO DATA(ls_un).
      DATA(lv_name) = COND string( WHEN ls_un-func_area IS INITIAL
                                   THEN `(no functional area on the posting)` ).
      READ TABLE lt_fa_text INTO DATA(ls_fa_text)
           WITH KEY func_area = ls_un-func_area.
      IF sy-subrc = 0.
        lv_name = ls_fa_text-name.
      ENDIF.

      line( |{ ls_un-func_area WIDTH = 6 } { lv_name WIDTH = 26 } | &&
            |{ ls_un-fiscal_year } { ls_un-items WIDTH = 8 ALIGN = RIGHT } | &&
            |{ ls_un-amount WIDTH = 20 ALIGN = RIGHT }| ).
    ENDLOOP.

    line( || ).
    line( |Each functional area above needs a decision from the functional| ).
    line( |team: which P&L line does it belong to? Add it to FILL_FUNCTIONAL_AREAS| ).
    line( |in ZCL_FI_PNL_SETUP and re-run - no report logic changes.| ).

  ENDMETHOD.


  METHOD type_text.
    CASE iv_type.
      WHEN 'X'. rv_text = 'Balance Sheet  <-- NOT P&L'.
      WHEN 'C'. rv_text = 'Cash Account   <-- NOT P&L'.
      WHEN 'N'. rv_text = 'Nonoperating Expense/Income'.
      WHEN 'P'. rv_text = 'Primary Costs / Revenue'.
      WHEN 'S'. rv_text = 'Secondary Costs'.
      WHEN OTHERS. rv_text = 'unknown'.
    ENDCASE.
  ENDMETHOD.


  METHOD line.
    mo_out->write( iv_text ).
  ENDMETHOD.

ENDCLASS.

