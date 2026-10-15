@EndUserText.label: 'P&L Report'

// This annotation is what makes it a *query* entity: when the OData
// service is called, the framework instantiates ZCL_FI_PNL_QUERY and
// calls its IF_RAP_QUERY_PROVIDER~SELECT method. There is no database
// table behind this entity - every row is built in ABAP.
@ObjectModel.query.implementedBy: 'ABAP:ZCL_FI_PNL_QUERY'

@UI.headerInfo: {
  typeName: 'P&L Row',
  typeNamePlural: 'P&L Rows'
}
define custom entity ZFI_PNL_C_REPORT
{
      // Running number 000001, 000002 ... in report order.
      // OData needs a key; the report itself has no natural one because
      // the same G/L account can appear under different nodes.
  key RowKey             : abap.numc(6);

      // ---------------- row identification ----------------
      NodeId             : abap.char(10);
      DisplayNo          : abap.char(10);
      Description        : abap.char(60);
      GLAccount          : abap.char(10);
      GLAccountLongName  : abap.char(50);
      FunctionalArea     : abap.char(16);

      // 'L' leaf / 'S' section total / 'T' subtotal - drives bold + borders
      RowType            : abap.char(1);
      // 0..3 - drives indentation
      NodeLevel          : abap.int4;
      // 'X' for the three major subtotals (Gross Profit, Profit from
      // Operations, Profit for the Year) - drives the shaded fill
      IsMajorSubtotal    : abap.char(1);

      // ---------------- the 14 amount columns ----------------
      @Semantics.amount.currencyCode: 'Currency'
      AmountPreviousYear : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountCurrentYear  : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod01     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod02     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod03     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod04     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod05     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod06     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod07     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod08     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod09     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod10     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod11     : abap.curr(23,2);
      @Semantics.amount.currencyCode: 'Currency'
      AmountPeriod12     : abap.curr(23,2);

      @Semantics.currencyCode: true
      Currency           : abap.cuky(5);

      // ---------------- selection fields (FSD 7) ----------------
      // These are never filled in the result. They exist so that the
      // client can send them as $filter values, which is how a RAP
      // unmanaged query receives its parameters.
      CompanyCode        : abap.char(4);
      Ledger             : abap.char(2);
      ReportingYear      : abap.numc(4);
      ReportingDate      : abap.dats;
      ViewMode           : abap.char(1);

      // Echo of what the selection actually resolved to, so the UI can
      // show "periods 001-003 are actuals, 004-012 forced to zero".
      LastActualPeriod   : abap.int4;
}
