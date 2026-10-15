"! <p class="shorttext synchronized">P&amp;L Report - Shared Types and Constants</p>
"! Central type pool for the P&amp;L report. Everything else in the build
"! refers to these types, so a length change only has to be made once.
INTERFACE zif_fi_pnl_types
  PUBLIC.

  " ------------------------------------------------------------------
  " Elementary types
  " ------------------------------------------------------------------
  " ABAP does not allow "TYPE c LENGTH 4" directly in a METHODS
  " declaration, so every parameter type used by the report is named here.
  TYPES ty_company_code TYPE c LENGTH 4.
  TYPES ty_ledger       TYPE c LENGTH 2.
  TYPES ty_fiscal_year  TYPE n LENGTH 4.
  TYPES ty_period       TYPE n LENGTH 3.
  TYPES ty_gl_account   TYPE c LENGTH 10.
  TYPES ty_func_area    TYPE c LENGTH 16.
  TYPES ty_node_id      TYPE c LENGTH 10.
  TYPES ty_view         TYPE c LENGTH 1.
  TYPES ty_date         TYPE d.
  TYPES ty_currency     TYPE c LENGTH 5.
  TYPES ty_amount       TYPE p LENGTH 15 DECIMALS 2.

  " ------------------------------------------------------------------
  " Row types in the report output
  " ------------------------------------------------------------------
  CONSTANTS:
    BEGIN OF gc_row_type,
      " one G/L account inside a section - only shown in the Detailed view
      leaf     TYPE c LENGTH 1 VALUE 'L',
      " section total: sum of that section's own G/L rows
      section  TYPE c LENGTH 1 VALUE 'S',
      " subtotal: sum of child nodes from ZFI_PNL_CHILD
      subtotal TYPE c LENGTH 1 VALUE 'T',
    END OF gc_row_type.

  CONSTANTS:
    BEGIN OF gc_label_source,
      fixed_text      TYPE c LENGTH 1 VALUE 'F',
      functional_area TYPE c LENGTH 1 VALUE 'A',
    END OF gc_label_source.

  CONSTANTS:
    BEGIN OF gc_view,
      detailed TYPE c LENGTH 1 VALUE 'D',
      summary  TYPE c LENGTH 1 VALUE 'S',
    END OF gc_view.

  " Technical key of the reconciliation line (FSD 2)
  CONSTANTS gc_unassigned_node TYPE ty_node_id  VALUE 'UNASSIGN'.

  " Default ledger. 0L = leading ledger.
  CONSTANTS gc_default_ledger  TYPE ty_ledger   VALUE '0L'.

  " The report always has exactly 12 period columns.
  CONSTANTS gc_period_count    TYPE i           VALUE 12.

  " ------------------------------------------------------------------
  " The 14 amount columns of one row, carried around as one value
  " ------------------------------------------------------------------
  TYPES ty_periods TYPE STANDARD TABLE OF ty_amount WITH EMPTY KEY.

  TYPES: BEGIN OF ty_vector,
           prev_year TYPE ty_amount,
           curr_year TYPE ty_amount,
           " always exactly 12 entries, index 1 = period 001
           periods   TYPE ty_periods,
         END OF ty_vector.

  " ------------------------------------------------------------------
  " Result of the single aggregated ledger read (FSD 4.1)
  " ------------------------------------------------------------------
  TYPES: BEGIN OF ty_agg,
           gl_account    TYPE ty_gl_account,
           func_area     TYPE ty_func_area,
           fiscal_year   TYPE ty_fiscal_year,
           fiscal_period TYPE ty_period,
           amount        TYPE ty_amount,
         END OF ty_agg.
  TYPES ty_agg_t TYPE STANDARD TABLE OF ty_agg WITH EMPTY KEY.

ENDINTERFACE.
