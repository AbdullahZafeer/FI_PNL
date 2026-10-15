"! <p class="shorttext synchronized">P&amp;L Report - Load Customizing</p>
"! Run this once with right-click -> Run As -> ABAP Application (F9).
"! It wipes and reloads the four ZFI_PNL_* tables from the FSD.
"!
"! Running it again is safe - it is a full reload, not an append. When
"! the functional team confirms one of the open mapping questions, change
"! the data here, run it again, and the report picks it up on the next
"! call. Nothing in the report logic has to be touched.
CLASS zcl_fi_pnl_setup DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    DATA mt_node   TYPE STANDARD TABLE OF zfi_pnl_node   WITH EMPTY KEY.
    DATA mt_child  TYPE STANDARD TABLE OF zfi_pnl_child  WITH EMPTY KEY.
    DATA mt_farea  TYPE STANDARD TABLE OF zfi_pnl_farea  WITH EMPTY KEY.
    DATA mt_gllist TYPE STANDARD TABLE OF zfi_pnl_gllist WITH EMPTY KEY.

    METHODS add_node
      IMPORTING iv_seq   TYPE i
                iv_id    TYPE string
                iv_no    TYPE string
                iv_desc  TYPE string
                iv_type  TYPE string
                iv_level TYPE i
                iv_major TYPE abap_bool DEFAULT abap_false.

    METHODS add_children
      IMPORTING iv_parent   TYPE string
                iv_children TYPE string_table.

    METHODS add_farea
      IMPORTING iv_node  TYPE string
                iv_areas TYPE string_table.

    METHODS add_gl_accounts
      IMPORTING iv_node     TYPE string
                iv_accounts TYPE string_table.

    METHODS fill_nodes.
    METHODS fill_composition.
    METHODS fill_functional_areas.
    METHODS fill_gl_lists.

ENDCLASS.


CLASS zcl_fi_pnl_setup IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    fill_nodes( ).
    fill_composition( ).
    fill_functional_areas( ).
    fill_gl_lists( ).

    DELETE FROM zfi_pnl_node.
    DELETE FROM zfi_pnl_child.
    DELETE FROM zfi_pnl_farea.
    DELETE FROM zfi_pnl_gllist.

    INSERT zfi_pnl_node   FROM TABLE @mt_node.
    INSERT zfi_pnl_child  FROM TABLE @mt_child.
    INSERT zfi_pnl_farea  FROM TABLE @mt_farea.
    INSERT zfi_pnl_gllist FROM TABLE @mt_gllist.

    COMMIT WORK.

    out->write( |P&L customizing loaded:| ).
    out->write( |  nodes           : { lines( mt_node ) }| ).
    out->write( |  composition     : { lines( mt_child ) }| ).
    out->write( |  functional areas: { lines( mt_farea ) }| ).
    out->write( |  revenue G/L     : { lines( mt_gllist ) }| ).

  ENDMETHOD.


  METHOD fill_nodes.

    " seq   technical id  display  description                              type level major
    add_node( iv_seq =  10 iv_id = 'SALES_LOC' iv_no = '0011' iv_desc = 'Sales Local'                            iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq =  20 iv_id = 'SALES_EXP' iv_no = '0012' iv_desc = 'Sales Export'                           iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq =  30 iv_id = 'REVENUE'   iv_no = '001'  iv_desc = 'Revenue from Contracts with Customers'  iv_type = 'T' iv_level = 1 ).
    add_node( iv_seq =  40 iv_id = 'COGS'      iv_no = '002'  iv_desc = 'Cost of Goods Sold'                     iv_type = 'S' iv_level = 1 ).
    add_node( iv_seq =  50 iv_id = 'GP'        iv_no = '003'  iv_desc = 'Gross Profit'                           iv_type = 'T' iv_level = 0 iv_major = abap_true ).
    add_node( iv_seq =  60 iv_id = 'SND'       iv_no = '004'  iv_desc = 'Sales and Distribution'                 iv_type = 'S' iv_level = 1 ).
    add_node( iv_seq =  70 iv_id = 'ADMIN'     iv_no = '005'  iv_desc = 'Administration'                         iv_type = 'S' iv_level = 1 ).
    add_node( iv_seq =  80 iv_id = 'OTHEXP'    iv_no = '006'  iv_desc = 'Other Expenses'                         iv_type = 'S' iv_level = 1 ).
    add_node( iv_seq =  90 iv_id = 'GAININV'   iv_no = '0071' iv_desc = 'Gain from Investments'                  iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq = 100 iv_id = 'OTHGAIN'   iv_no = '0072' iv_desc = 'Other Gains'                            iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq = 110 iv_id = 'OTHINC'    iv_no = '007'  iv_desc = 'Other Income'                           iv_type = 'T' iv_level = 1 ).
    add_node( iv_seq = 120 iv_id = 'PFO'       iv_no = '008'  iv_desc = 'Profit from Operations'                 iv_type = 'T' iv_level = 0 iv_major = abap_true ).
    add_node( iv_seq = 130 iv_id = 'INTGAIN'   iv_no = '0091' iv_desc = 'Interest & Other Gains'                 iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq = 140 iv_id = 'INTCOST'   iv_no = '0092' iv_desc = 'Interest & Other Costs'                 iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq = 150 iv_id = 'FINCOST'   iv_no = '009'  iv_desc = 'Finance Cost'                           iv_type = 'T' iv_level = 1 ).
    add_node( iv_seq = 160 iv_id = 'PBT'       iv_no = '010'  iv_desc = 'Profit / Loss Before Taxation'          iv_type = 'T' iv_level = 0 ).
    add_node( iv_seq = 170 iv_id = 'INCTAX'    iv_no = '0111' iv_desc = 'Taxes from Income and Revenue'          iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq = 180 iv_id = 'OTHTAX'    iv_no = '0112' iv_desc = 'Other Taxes'                            iv_type = 'S' iv_level = 2 ).
    add_node( iv_seq = 190 iv_id = 'TAXEXP'    iv_no = '011'  iv_desc = 'Income Tax Expense / Credit'            iv_type = 'T' iv_level = 1 ).
    " Reconciliation line - anything the mapping did not catch lands here.
    add_node( iv_seq = 200 iv_id = 'UNASSIGN'  iv_no = ''     iv_desc = 'Unassigned'                             iv_type = 'S' iv_level = 1 ).
    add_node( iv_seq = 210 iv_id = 'PFY'       iv_no = '012'  iv_desc = 'Profit / Loss for the Year'             iv_type = 'T' iv_level = 0 iv_major = abap_true ).

  ENDMETHOD.


  METHOD fill_composition.

    add_children( iv_parent = 'REVENUE' iv_children = VALUE #( ( `SALES_LOC` ) ( `SALES_EXP` ) ) ).
    add_children( iv_parent = 'GP'      iv_children = VALUE #( ( `REVENUE` ) ( `COGS` ) ) ).
    add_children( iv_parent = 'OTHINC'  iv_children = VALUE #( ( `GAININV` ) ( `OTHGAIN` ) ) ).
    add_children( iv_parent = 'PFO'     iv_children = VALUE #( ( `GP` ) ( `SND` ) ( `ADMIN` ) ( `OTHEXP` ) ( `OTHINC` ) ) ).
    add_children( iv_parent = 'FINCOST' iv_children = VALUE #( ( `INTGAIN` ) ( `INTCOST` ) ) ).
    add_children( iv_parent = 'PBT'     iv_children = VALUE #( ( `PFO` ) ( `FINCOST` ) ) ).
    add_children( iv_parent = 'TAXEXP'  iv_children = VALUE #( ( `INCTAX` ) ( `OTHTAX` ) ) ).
    add_children( iv_parent = 'PFY'     iv_children = VALUE #( ( `PBT` ) ( `TAXEXP` ) ( `UNASSIGN` ) ) ).

  ENDMETHOD.


  METHOD fill_functional_areas.

    " FSD 5 - confirmed mapping.
    " COGS is fed by three functional areas. They are NOT shown as three
    " sub-headings: all their G/L rows appear together under the single
    " "Cost of Goods Sold" section.
    add_farea( iv_node = 'COGS'    iv_areas = VALUE #( ( `YB18` ) ( `YB20` ) ( `YB99` ) ) ).
    add_farea( iv_node = 'SND'     iv_areas = VALUE #( ( `YB30` ) ) ).
    add_farea( iv_node = 'ADMIN'   iv_areas = VALUE #( ( `YB40` ) ) ).
    add_farea( iv_node = 'OTHEXP'  iv_areas = VALUE #( ( `YB75` ) ) ).
    add_farea( iv_node = 'GAININV' iv_areas = VALUE #( ( `YB77` ) ) ).
    add_farea( iv_node = 'OTHGAIN' iv_areas = VALUE #( ( `YB70` ) ) ).
    add_farea( iv_node = 'INTGAIN' iv_areas = VALUE #( ( `YB81` ) ) ).
    add_farea( iv_node = 'INTCOST' iv_areas = VALUE #( ( `YB85` ) ) ).
    add_farea( iv_node = 'INCTAX'  iv_areas = VALUE #( ( `YB90` ) ) ).
    add_farea( iv_node = 'OTHTAX'  iv_areas = VALUE #( ( `YB98` ) ) ).

    " Deliberately NOT mapped, so their postings show up in "Unassigned":
    "   YB60 YB61 YB62 YB79 YB83 YB87 YB89  - open item 1 in the FSD
    " Deliberately not mapped and confirmed as not used:
    "   YB15 YB25 YB35 YB50
    " When the functional team confirms one, add a line above and re-run.

  ENDMETHOD.


  METHOD fill_gl_lists.

    " Annex A - FSD 6. Written as plain 8-digit numbers; ADD_GL_ACCOUNTS
    " pads them to the 10-character internal form.
    add_gl_accounts( iv_node = 'SALES_LOC' iv_accounts = VALUE #(
      ( `41000000` ) ( `41000001` ) ( `41000002` ) ( `41000400` )
      ( `44000000` ) ( `44001000` ) ( `44002000` ) ( `44002001` )
      ( `44002002` ) ( `44002200` ) ( `44002201` ) ( `44003000` )
      ( `44006000` ) ( `44910000` ) ) ).

    add_gl_accounts( iv_node = 'SALES_EXP' iv_accounts = VALUE #(
      ( `41001000` ) ( `41001001` ) ( `41001002` ) ( `41940000` )
      ( `44002003` ) ( `44002004` ) ( `44002100` ) ( `44002202` )
      ( `44003100` ) ( `44020003` ) ( `44020004` ) ( `44940000` ) ) ).

  ENDMETHOD.


  METHOD add_node.
    APPEND VALUE #( node_id      = iv_id
                    display_seq  = iv_seq
                    display_no   = iv_no
                    description  = iv_desc
                    row_type     = iv_type
                    node_level   = iv_level
                    label_source = 'F'
                    is_major     = COND #( WHEN iv_major = abap_true THEN 'X' ) )
           TO mt_node.
  ENDMETHOD.


  METHOD add_children.
    DATA(lv_seq) = 0.
    LOOP AT iv_children INTO DATA(lv_child).
      lv_seq = lv_seq + 10.
      APPEND VALUE #( parent_node = iv_parent
                      child_node  = lv_child
                      child_seq   = lv_seq ) TO mt_child.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_farea.
    LOOP AT iv_areas INTO DATA(lv_area).
      APPEND VALUE #( func_area = lv_area
                      node_id   = iv_node ) TO mt_farea.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_gl_accounts.
    DATA(lv_seq) = 0.
    LOOP AT iv_accounts INTO DATA(lv_account).
      lv_seq = lv_seq + 10.
      " ALPHA conversion: 41000000 -> 0041000000. I_JournalEntryItem
      " stores GLAccount with leading zeros, so without this the config
      " would never match a single posting and every revenue row would
      " come out as zero.
      APPEND VALUE #( gl_account = |{ lv_account ALPHA = IN }|
                      node_id    = iv_node
                      gl_seq     = lv_seq ) TO mt_gllist.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

