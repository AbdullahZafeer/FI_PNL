"! <p class="shorttext synchronized">P&amp;L Report - Row Builder</p>
"! Turns one selection (company code / ledger / year / date / view) into
"! the finished list of report rows.
"!
"! Sequence inside BUILD:
"!   1. read_config        - the four ZFI_PNL_* customizing tables
"!   2. read_company_code  - chart of accounts + company code currency
"!   3. determine_period   - the cutoff, delegated to ZCL_FI_PNL_PERIOD
"!   4. read_ledger        - ONE aggregated SELECT on I_JournalEntryItem
"!   5. build_leaves       - assign every posting to exactly one node
"!   6. assemble           - emit rows top to bottom, rolling up subtotals
"!
"! Sign convention: amounts are taken from the ledger unchanged. Revenue
"! therefore shows as negative and a profit shows as negative, exactly as
"! in the source workbook. No sign is flipped anywhere.
CLASS zcl_fi_pnl_builder DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES ty_rows TYPE STANDARD TABLE OF zfi_pnl_c_report WITH EMPTY KEY.

    METHODS constructor
      IMPORTING iv_company_code   TYPE zif_fi_pnl_types=>ty_company_code
                iv_ledger         TYPE zif_fi_pnl_types=>ty_ledger
                                       DEFAULT zif_fi_pnl_types=>gc_default_ledger
                iv_reporting_year TYPE zif_fi_pnl_types=>ty_fiscal_year OPTIONAL
                iv_reporting_date TYPE zif_fi_pnl_types=>ty_date        OPTIONAL
                iv_view           TYPE zif_fi_pnl_types=>ty_view
                                       DEFAULT zif_fi_pnl_types=>gc_view-detailed.

    METHODS build
      RETURNING VALUE(rt_rows) TYPE ty_rows.

  PRIVATE SECTION.

    " ---------------- internal working types ----------------
    TYPES: BEGIN OF ty_leaf,
             node_id    TYPE zif_fi_pnl_types=>ty_node_id,
             gl_account TYPE zif_fi_pnl_types=>ty_gl_account,
             func_area  TYPE zif_fi_pnl_types=>ty_func_area,
             vector     TYPE zif_fi_pnl_types=>ty_vector,
           END OF ty_leaf.
    " Sorted by node then account: the LOOP ... WHERE node_id = ... in
    " ASSEMBLE then reads the leaves of a section already in account order.
    TYPES ty_leaf_t TYPE SORTED TABLE OF ty_leaf
                         WITH UNIQUE KEY node_id gl_account.

    TYPES ty_node_desc TYPE c LENGTH 60.

    TYPES: BEGIN OF ty_total,
             node_id TYPE zif_fi_pnl_types=>ty_node_id,
             vector  TYPE zif_fi_pnl_types=>ty_vector,
           END OF ty_total.
    TYPES ty_total_t TYPE HASHED TABLE OF ty_total WITH UNIQUE KEY node_id.

    TYPES: BEGIN OF ty_text,
             id   TYPE c LENGTH 16,
             text TYPE c LENGTH 50,
           END OF ty_text.
    TYPES ty_text_t TYPE HASHED TABLE OF ty_text WITH UNIQUE KEY id.

    " ---------------- selection ----------------
    DATA mv_company_code   TYPE zif_fi_pnl_types=>ty_company_code.
    DATA mv_ledger         TYPE zif_fi_pnl_types=>ty_ledger.
    DATA mv_reporting_year TYPE zif_fi_pnl_types=>ty_fiscal_year.
    DATA mv_reporting_date TYPE zif_fi_pnl_types=>ty_date.
    DATA mv_view           TYPE zif_fi_pnl_types=>ty_view.

    " ---------------- derived context ----------------
    DATA ms_sel      TYPE zcl_fi_pnl_period=>ty_selection.
    DATA mv_coa      TYPE c LENGTH 4.
    DATA mv_currency TYPE zif_fi_pnl_types=>ty_currency.

    " ---------------- configuration ----------------
    DATA mt_node   TYPE STANDARD TABLE OF zfi_pnl_node WITH EMPTY KEY.
    DATA mt_child  TYPE SORTED TABLE OF zfi_pnl_child
                        WITH NON-UNIQUE KEY parent_node child_seq child_node.
    DATA mt_farea  TYPE HASHED TABLE OF zfi_pnl_farea WITH UNIQUE KEY func_area.
    DATA mt_gllist TYPE HASHED TABLE OF zfi_pnl_gllist WITH UNIQUE KEY gl_account.

    " ---------------- working data ----------------
    DATA mt_agg     TYPE zif_fi_pnl_types=>ty_agg_t.
    DATA mt_leaf    TYPE ty_leaf_t.
    DATA mt_total   TYPE ty_total_t.
    DATA mt_gl_text TYPE ty_text_t.
    DATA mt_fa_text TYPE ty_text_t.
    DATA mv_rowkey  TYPE i.

    METHODS read_config.
    METHODS read_company_code.
    METHODS read_ledger.
    METHODS build_leaves.
    METHODS read_texts.
    METHODS assemble RETURNING VALUE(rt_rows) TYPE ty_rows.
    METHODS node_description
  IMPORTING is_node        TYPE zfi_pnl_node
  RETURNING VALUE(rv_text) TYPE ty_node_desc.
    " ---------------- amount vector helpers ----------------
    CLASS-METHODS new_vector
      RETURNING VALUE(rs_vector) TYPE zif_fi_pnl_types=>ty_vector.
    CLASS-METHODS add_vector
      IMPORTING is_add    TYPE zif_fi_pnl_types=>ty_vector
      CHANGING  cs_vector TYPE zif_fi_pnl_types=>ty_vector.
    CLASS-METHODS sum_periods
      IMPORTING is_vector     TYPE zif_fi_pnl_types=>ty_vector
      RETURNING VALUE(rv_sum) TYPE zif_fi_pnl_types=>ty_amount.
    CLASS-METHODS set_amounts
      IMPORTING is_vector TYPE zif_fi_pnl_types=>ty_vector
      CHANGING  cs_row    TYPE zfi_pnl_c_report.

ENDCLASS.


CLASS zcl_fi_pnl_builder IMPLEMENTATION.

  METHOD constructor.
    mv_company_code   = iv_company_code.
    mv_ledger         = COND #( WHEN iv_ledger IS INITIAL
                                THEN zif_fi_pnl_types=>gc_default_ledger
                                ELSE iv_ledger ).
    mv_reporting_year = iv_reporting_year.
    mv_reporting_date = iv_reporting_date.
    mv_view           = COND #( WHEN iv_view IS INITIAL
                                THEN zif_fi_pnl_types=>gc_view-detailed
                                ELSE iv_view ).
  ENDMETHOD.


  METHOD build.

    read_config( ).
    IF mt_node IS INITIAL.
      " Customizing has not been loaded yet - run ZCL_FI_PNL_SETUP once.
      RETURN.
    ENDIF.

    read_company_code( ).

    ms_sel = zcl_fi_pnl_period=>determine_selection(
               iv_company_code   = mv_company_code
               iv_reporting_year = mv_reporting_year
               iv_reporting_date = mv_reporting_date ).

    " Neither Reporting Year nor a resolvable Reporting Date was given.
    IF ms_sel-fiscal_year IS INITIAL.
      RETURN.
    ENDIF.

    read_ledger( ).
    build_leaves( ).
    read_texts( ).

    rt_rows = assemble( ).

  ENDMETHOD.


  METHOD read_config.

    SELECT FROM zfi_pnl_node FIELDS *
      ORDER BY display_seq
      INTO TABLE @mt_node.

    SELECT FROM zfi_pnl_child FIELDS * INTO TABLE @mt_child.
    SELECT FROM zfi_pnl_farea FIELDS * INTO TABLE @mt_farea.
    SELECT FROM zfi_pnl_gllist FIELDS * INTO TABLE @mt_gllist.

  ENDMETHOD.


  METHOD read_company_code.

    SELECT SINGLE ChartOfAccounts, Currency
      FROM I_CompanyCode
      WHERE CompanyCode = @mv_company_code
      INTO ( @mv_coa, @mv_currency ).

  ENDMETHOD.


  METHOD read_ledger.

    " ----------------------------------------------------------------
    " FSD 4.1: ONE aggregated read, never one call per account.
    "
    " The join to I_GLAccountInChartOfAccounts restricts the result to
    " P&L accounts. Without it, balance sheet postings would land in the
    " "Unassigned" line and Profit for the Year would be meaningless.
    "   N = non-operating expense or income
    "   P = primary costs / revenue
    "   S = secondary costs
    "   X = balance sheet  (excluded)
    "
    " *** VERIFY IN ADT ***: confirm I_GLAccountInChartOfAccounts and its
    " GLAccountType field are released on the tenant (FSD 10).
    " ----------------------------------------------------------------
    SELECT FROM I_JournalEntryItem AS je
      INNER JOIN I_GLAccountInChartOfAccounts AS gl
              ON  gl~ChartOfAccounts = @mv_coa
              AND gl~GLAccount       = je~GLAccount
      FIELDS je~GLAccount                          AS gl_account,
             je~FunctionalArea                     AS func_area,
             je~FiscalYear                         AS fiscal_year,
             je~FiscalPeriod                       AS fiscal_period,
             SUM( je~AmountInCompanyCodeCurrency )  AS amount
      WHERE je~CompanyCode = @mv_company_code
        AND je~Ledger      = @mv_ledger
        AND je~FiscalYear  IN ( @ms_sel-fiscal_year, @ms_sel-prev_fiscal_year )
*        AND gl~GLAccountType IN ( 'N', 'P', 'S' ) - Edited by - Abdullah Zafeer on 06-10-2026
        AND gl~GLAccountType IN ( 'N', 'P' )
      GROUP BY je~GLAccount, je~FunctionalArea, je~FiscalYear, je~FiscalPeriod
      INTO CORRESPONDING FIELDS OF TABLE @mt_agg.

  ENDMETHOD.


  METHOD build_leaves.

    DATA ls_leaf TYPE ty_leaf.

    LOOP AT mt_agg INTO DATA(ls_agg).

      " ------------------------------------------------------------
      " The report has twelve period columns and only twelve. Anything
      " posted outside 001-012 is dropped here, before it can create a
      " row, so an account posted only in a special period does not
      " appear as an all-zero line.
      "
      "   period 000     balance carry-forward. P&L accounts are closed
      "                  to retained earnings, so nothing should land
      "                  here; if something does, it is a data issue.
      "   periods 13-16  special year-end adjustment periods. CONFIRMED
      "                  as not reported. Note the consequence: if the
      "                  company ever posts in a special period, Profit
      "                  for the Year will not tie back to the ledger by
      "                  that amount. Worth one check at UAT.
      " ------------------------------------------------------------
      DATA(lv_idx) = CONV i( ls_agg-fiscal_period ).
      IF lv_idx < 1 OR lv_idx > zif_fi_pnl_types=>gc_period_count.
        CONTINUE.
      ENDIF.

      " ------------------------------------------------------------
      " Assign the posting to exactly one node, in this order:
      "   1. the fixed revenue G/L list (Annex A) wins
      "   2. otherwise the functional area mapping
      "   3. otherwise the Unassigned reconciliation line
      " Because both config tables are keyed by the lookup field, a
      " posting can never be counted twice.
      " ------------------------------------------------------------
      DATA(lv_node) = zif_fi_pnl_types=>gc_unassigned_node.

      READ TABLE mt_gllist INTO DATA(ls_gl)
           WITH TABLE KEY gl_account = ls_agg-gl_account.
      IF sy-subrc = 0.
        lv_node = ls_gl-node_id.
      ELSE.
        READ TABLE mt_farea INTO DATA(ls_fa)
             WITH TABLE KEY func_area = ls_agg-func_area.
        IF sy-subrc = 0.
          lv_node = ls_fa-node_id.
        ENDIF.
      ENDIF.

      READ TABLE mt_leaf ASSIGNING FIELD-SYMBOL(<ls_leaf>)
           WITH TABLE KEY node_id = lv_node gl_account = ls_agg-gl_account.
      IF sy-subrc <> 0.
        CLEAR ls_leaf.
        ls_leaf-node_id    = lv_node.
        ls_leaf-gl_account = ls_agg-gl_account.
        ls_leaf-func_area  = ls_agg-func_area.
        ls_leaf-vector     = new_vector( ).
        INSERT ls_leaf INTO TABLE mt_leaf ASSIGNING <ls_leaf>.
      ENDIF.

      " ------------------------------------------------------------
      " Which of the 14 columns does this amount belong to?
      " ------------------------------------------------------------
      IF ls_agg-fiscal_year = ms_sel-prev_fiscal_year.

        " Previous Year is the full prior fiscal year, periods 001-012,
        " never affected by the Reporting Date cutoff (FSD 7).
        <ls_leaf>-vector-prev_year = <ls_leaf>-vector-prev_year + ls_agg-amount.

      ELSEIF ls_agg-fiscal_year = ms_sel-fiscal_year.

        " The cutoff: everything after the last actual period is forced
        " to zero, whether or not postings exist there (FSD 7).
        IF lv_idx > ms_sel-last_period.
          CONTINUE.
        ENDIF.

        <ls_leaf>-vector-periods[ lv_idx ] =
          <ls_leaf>-vector-periods[ lv_idx ] + ls_agg-amount.

      ENDIF.

    ENDLOOP.

    " ----------------------------------------------------------------
    " Revenue accounts from Annex A are always shown, even with no
    " postings, so the layout of the two revenue sections stays stable.
    " Sections fed by functional area only show accounts that were
    " actually posted to.
    " ----------------------------------------------------------------
    LOOP AT mt_gllist INTO ls_gl.
      READ TABLE mt_leaf TRANSPORTING NO FIELDS
           WITH TABLE KEY node_id = ls_gl-node_id gl_account = ls_gl-gl_account.
      IF sy-subrc <> 0.
        CLEAR ls_leaf.
        ls_leaf-node_id    = ls_gl-node_id.
        ls_leaf-gl_account = ls_gl-gl_account.
        ls_leaf-vector     = new_vector( ).
        INSERT ls_leaf INTO TABLE mt_leaf.
      ENDIF.
    ENDLOOP.

    " Current Year is the SUM of the 12 period columns rather than a
    " separate total. That guarantees acceptance criterion 2: the period
    " columns always add up to the Current Year column, cutoff included.
    LOOP AT mt_leaf ASSIGNING <ls_leaf>.
      <ls_leaf>-vector-curr_year = sum_periods( <ls_leaf>-vector ).
    ENDLOOP.

  ENDMETHOD.


  METHOD read_texts.

    " G/L account long texts, only for the accounts actually on the report.
    " *** VERIFY IN ADT ***: field name GLAccountLongName in I_GLAccountText.
    IF mt_leaf IS NOT INITIAL.
      SELECT FROM I_GLAccountText
        FIELDS GLAccount AS id, GLAccountLongName AS text
        FOR ALL ENTRIES IN @mt_leaf
        WHERE ChartOfAccounts = @mv_coa
          AND GLAccount       = @mt_leaf-gl_account
          AND Language        = @sy-langu
        INTO CORRESPONDING FIELDS OF TABLE @mt_gl_text.
    ENDIF.

    " Functional area texts, for nodes configured with LABEL_SOURCE = 'A'.
    SELECT FROM I_FunctionalAreaText
      FIELDS FunctionalArea AS id, FunctionalAreaName AS text
      WHERE Language = @sy-langu
      INTO CORRESPONDING FIELDS OF TABLE @mt_fa_text.

  ENDMETHOD.


  METHOD node_description.

    " Fixed text is the normal case; the P&L wording ("Revenue from
    " Contracts with Customers") does not match the functional area
    " master text, so it is held in ZFI_PNL_NODE.
    rv_text = is_node-description.

    IF is_node-label_source = zif_fi_pnl_types=>gc_label_source-functional_area.
      LOOP AT mt_farea INTO DATA(ls_fa) WHERE node_id = is_node-node_id.
        READ TABLE mt_fa_text INTO DATA(ls_txt) WITH TABLE KEY id = ls_fa-func_area.
        IF sy-subrc = 0 AND ls_txt-text IS NOT INITIAL.
          rv_text = ls_txt-text.
        ENDIF.
        EXIT.   " first functional area of the node decides the label
      ENDLOOP.
    ENDIF.

  ENDMETHOD.


  METHOD assemble.

    DATA ls_row TYPE zfi_pnl_c_report.

    CLEAR: mt_total, mv_rowkey.

    " The node table is read in DISPLAY_SEQ order and the row order is
    " dependency-ordered (FSD 2), so by the time a subtotal is reached
    " every child it needs is already in MT_TOTAL. One single pass,
    " top to bottom - no recursion needed.
    LOOP AT mt_node INTO DATA(ls_node).

      DATA(ls_vector) = new_vector( ).

      IF ls_node-row_type = zif_fi_pnl_types=>gc_row_type-section.

        " ---------- section: total of its own G/L rows ----------
        LOOP AT mt_leaf INTO DATA(ls_leaf) WHERE node_id = ls_node-node_id.

          add_vector( EXPORTING is_add    = ls_leaf-vector
                      CHANGING  cs_vector = ls_vector ).

          " Leaf rows only exist in the Detailed view (FSD 3).
          IF mv_view = zif_fi_pnl_types=>gc_view-detailed.
            CLEAR ls_row.
            mv_rowkey            = mv_rowkey + 1.
            ls_row-rowkey        = mv_rowkey.
            ls_row-nodeid        = ls_node-node_id.
            " All three Cost of Goods Sold functional areas share the one
            " section description - the section is never split by
            " functional area (FSD 5).
            ls_row-description   = node_description( ls_node ).
            ls_row-glaccount     = ls_leaf-gl_account.
            ls_row-functionalarea = ls_leaf-func_area.
            READ TABLE mt_gl_text INTO DATA(ls_gtxt)
                 WITH TABLE KEY id = ls_leaf-gl_account.
            IF sy-subrc = 0.
              ls_row-glaccountlongname = ls_gtxt-text.
            ENDIF.
            ls_row-rowtype       = zif_fi_pnl_types=>gc_row_type-leaf.
            ls_row-nodelevel     = ls_node-node_level + 1.
            set_amounts( EXPORTING is_vector = ls_leaf-vector
                         CHANGING  cs_row    = ls_row ).
            ls_row-currency         = mv_currency.
            ls_row-companycode      = mv_company_code.
            ls_row-ledger           = mv_ledger.
            ls_row-reportingyear    = ms_sel-fiscal_year.
            ls_row-reportingdate    = mv_reporting_date.
            ls_row-viewmode         = mv_view.
            ls_row-lastactualperiod = ms_sel-last_period.
            APPEND ls_row TO rt_rows.
          ENDIF.

        ENDLOOP.

      ELSE.

        " ---------- subtotal: total of its child nodes ----------
        LOOP AT mt_child INTO DATA(ls_child) WHERE parent_node = ls_node-node_id.
          READ TABLE mt_total INTO DATA(ls_total)
               WITH TABLE KEY node_id = ls_child-child_node.
          IF sy-subrc = 0.
            add_vector( EXPORTING is_add    = ls_total-vector
                        CHANGING  cs_vector = ls_vector ).
          ENDIF.
        ENDLOOP.

      ENDIF.

      " Remember the node total so later subtotals can pick it up.
      INSERT VALUE #( node_id = ls_node-node_id vector = ls_vector )
             INTO TABLE mt_total.

      " ---------- the node's own row ----------
      CLEAR ls_row.
      mv_rowkey               = mv_rowkey + 1.
      ls_row-rowkey           = mv_rowkey.
      ls_row-nodeid           = ls_node-node_id.
      ls_row-displayno        = ls_node-display_no.
      ls_row-description      = node_description( ls_node ).
      ls_row-rowtype          = ls_node-row_type.
      ls_row-nodelevel        = ls_node-node_level.
      ls_row-ismajorsubtotal  = ls_node-is_major.
      set_amounts( EXPORTING is_vector = ls_vector
                   CHANGING  cs_row    = ls_row ).
      ls_row-currency         = mv_currency.
      ls_row-companycode      = mv_company_code.
      ls_row-ledger           = mv_ledger.
      ls_row-reportingyear    = ms_sel-fiscal_year.
      ls_row-reportingdate    = mv_reporting_date.
      ls_row-viewmode         = mv_view.
      ls_row-lastactualperiod = ms_sel-last_period.
      APPEND ls_row TO rt_rows.

    ENDLOOP.

  ENDMETHOD.


  METHOD new_vector.
    " Always exactly 12 entries, so PERIODS[ n ] is safe for n = 1..12.
    DO zif_fi_pnl_types=>gc_period_count TIMES.
      APPEND 0 TO rs_vector-periods.
    ENDDO.
  ENDMETHOD.


  METHOD add_vector.
    cs_vector-prev_year = cs_vector-prev_year + is_add-prev_year.
    cs_vector-curr_year = cs_vector-curr_year + is_add-curr_year.
    DO zif_fi_pnl_types=>gc_period_count TIMES.
      cs_vector-periods[ sy-index ] =
        cs_vector-periods[ sy-index ] + is_add-periods[ sy-index ].
    ENDDO.
  ENDMETHOD.


  METHOD sum_periods.
    LOOP AT is_vector-periods INTO DATA(lv_amount).
      rv_sum = rv_sum + lv_amount.
    ENDLOOP.
  ENDMETHOD.


  METHOD set_amounts.
    cs_row-amountpreviousyear = is_vector-prev_year.
    cs_row-amountcurrentyear  = is_vector-curr_year.
    " AMOUNTPERIOD01 .. AMOUNTPERIOD12, addressed dynamically so the
    " twelve assignments do not have to be written out by hand.
    DO zif_fi_pnl_types=>gc_period_count TIMES.
      ASSIGN COMPONENT |AMOUNTPERIOD{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
             OF STRUCTURE cs_row TO FIELD-SYMBOL(<lv_field>).
      IF sy-subrc = 0.
        <lv_field> = is_vector-periods[ sy-index ].
      ENDIF.
    ENDDO.
  ENDMETHOD.

ENDCLASS.

