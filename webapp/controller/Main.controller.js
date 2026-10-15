sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/ui/model/json/JSONModel",
	"sap/ui/model/Filter",
	"sap/ui/model/FilterOperator",
	"sap/m/MessageBox",
	"sap/m/MessageToast"
], function (Controller, JSONModel, Filter, FilterOperator, MessageBox, MessageToast) {
	"use strict";

	// The OData entity set exposed by ZFI_PNL_REPORT.
	var ENTITY_SET = "/PnLReport";

	// How many rows the Excel export asks for per request. The export must
	// contain the whole report regardless of what is on screen (FSD 9), so
	// it pages through the service itself rather than reading the table.
	var EXPORT_PAGE_SIZE = 500;

	// Negative numbers as (1,234) rather than red text. This is still open
	// item 4 in the FSD; it is deliberately in exactly two places - the
	// fmtAmount formatter below, and EXCEL_NUMBER_FORMAT.
	//
	// Three sections: positive; negative; zero. The zero section renders a
	// dash, matching fmtAmount, so a zero row reads the same on screen and
	// in the file.
	var EXCEL_NUMBER_FORMAT = "#,##0;(#,##0);\"-\"";

	// Static month names, period 001 first. Searle runs a July-June fiscal
	// year, so period 001 is July (FSD 9 - no year in the header text).
	var MONTHS = ["July", "August", "September", "October", "November", "December",
		"January", "February", "March", "April", "May", "June"];

	// Legal entity name printed above the report. The PnLReport entity has
	// no company name field, so it is kept here per company code; anything
	// not listed falls back to "Company Code nnnn".
	var COMPANY_NAMES = {
		"1000": "Searle Pakistan (Pvt) Ltd."
	};

	// Excel row shading, lightest to darkest: section headings, totals,
	// and the three major subtotals (Gross Profit, Profit from
	// Operations, Profit for the Year), which must still stand out from
	// the ordinary totals.
	var EXCEL_FILL_HEADING = "FFF2F2F2";
	var EXCEL_FILL_TOTAL = "FFD9D9D9";
	var EXCEL_FILL_MAJOR = "FFBFBFBF";

	return Controller.extend("zfipnl.controller.Main", {

		/* ============================================================
		 * lifecycle
		 * ============================================================ */

		onInit: function () {
			this.oUiModel = new JSONModel({
				companyCode: "1000",
				reportingYear: String(new Date().getFullYear()),
				reportingDate: "",
				viewMode: "D",
				hasData: false,
				status: "",
				companyName: ""
			});
			this.getView().setModel(this.oUiModel, "ui");

			// The table shows the restructured rows from _withSectionHeadings,
			// not the OData list directly, so it reads from a JSON model. The
			// default size limit of 100 would silently cut the report off.
			this.oRowsModel = new JSONModel([]);
			this.oRowsModel.setSizeLimit(100000);
			this.getView().setModel(this.oRowsModel, "rows");
		},

		/* ============================================================
		 * selection
		 * ============================================================ */

		/**
		 * Turns the selection bar into OData filters.
		 *
		 * These are not really filters - the backend is a RAP unmanaged
		 * query, and $filter is simply how it receives its parameters.
		 * That is why every one of them is EQ and why leaving one out
		 * changes what the report calculates rather than which rows come
		 * back.
		 */
		_buildFilters: function () {
			var oData = this.oUiModel.getData();
			var aFilters = [
				new Filter("CompanyCode", FilterOperator.EQ, oData.companyCode),
				new Filter("ViewMode", FilterOperator.EQ, oData.viewMode)
			];

			if (oData.reportingYear) {
				aFilters.push(new Filter("ReportingYear", FilterOperator.EQ, oData.reportingYear));
			}
			if (oData.reportingDate) {
				aFilters.push(new Filter("ReportingDate", FilterOperator.EQ, oData.reportingDate));
			}
			return aFilters;
		},

		_validate: function () {
			var oData = this.oUiModel.getData();
			var oBundle = this.getView().getModel("i18n").getResourceBundle();

			if (!oData.companyCode) {
				MessageBox.error(oBundle.getText("errCompanyCode"));
				return false;
			}
			if (!oData.reportingYear && !oData.reportingDate) {
				MessageBox.error(oBundle.getText("errYearOrDate"));
				return false;
			}
			return true;
		},

		onGo: function () {
			if (!this._validate()) {
				return;
			}

			var that = this;
			var oTable = this.byId("pnlTable");
			var oBundle = this.getView().getModel("i18n").getResourceBundle();

			oTable.setBusy(true);
			this.oUiModel.setProperty("/hasData", false);
			this.oUiModel.setProperty("/companyName", this._companyName());

			this._fetchAllRows()
				.then(function (aRows) {
					var iCount = aRows.length;
					that.oRowsModel.setData(that._withSectionHeadings(aRows));
					that.oUiModel.setProperty("/hasData", iCount > 0);

					// Currency and the cutoff period are the same on every
					// row, so read them off the first one. Showing the
					// cutoff matters: with a Reporting Date set, later
					// periods are forced to zero, and a column of zeros
					// otherwise looks like missing data.
					var sStatus = oBundle.getText("rowCount", [iCount]);
					if (iCount) {
						sStatus += oBundle.getText("statusDetail", [
							aRows[0].Currency || "",
							aRows[0].LastActualPeriod
						]);
					}
					that.oUiModel.setProperty("/status", sStatus);

					if (iCount === 0) {
						// The report always returns its fixed node rows,
						// even with no postings. Zero rows therefore means
						// the selection never reached the builder, or the
						// ZFI_PNL_* customizing is empty.
						MessageToast.show(oBundle.getText("noRowsHint"), { duration: 6000 });
					}
				})
				.catch(function (oError) {
					that.oRowsModel.setData([]);
					that.oUiModel.setProperty("/status", "");
					MessageBox.error(oError && oError.message ? oError.message : String(oError));
				})
				.finally(function () {
					oTable.setBusy(false);
				});
		},

		/* ============================================================
		 * section headings
		 * ============================================================ */

		/**
		 * Adds a heading row above every section's G/L accounts and turns
		 * that section's total row into "Total <section>".
		 *
		 * The service returns a section as its account rows (RowType L)
		 * followed directly by the section row (RowType S) with the same
		 * NodeId, which carries the number and the total. The heading is a
		 * copy of that S row's number and text with no amounts, put in
		 * front of the first account. Sections without account rows (all
		 * of them in the Summary view) have nothing to head, so they stay
		 * a single "0071 Gain from Investments"-style row.
		 *
		 * Heading rows exist only in the app (RowType H); nothing here
		 * changes an amount or the row order the backend decided.
		 */
		_withSectionHeadings: function (aRows) {
			var aOut = [];

			aRows.forEach(function (oRow, i) {
				var oPrev = aRows[i - 1];
				var bFirstLeaf = oRow.RowType === "L" &&
					!(oPrev && oPrev.RowType === "L" && oPrev.NodeId === oRow.NodeId);

				if (bFirstLeaf) {
					var oSection = this._sectionRowAfter(aRows, i);
					aOut.push({
						RowKey: "H_" + oRow.NodeId + "_" + i,
						NodeId: oRow.NodeId,
						RowType: "H",
						NodeLevel: oSection ? oSection.NodeLevel : Math.max((Number(oRow.NodeLevel) || 1) - 1, 0),
						DisplayNo: oSection ? oSection.DisplayNo : "",
						Description: oSection ? oSection.Description : oRow.Description,
						IsMajorSubtotal: ""
					});
				}

				if (oRow.RowType === "S" && oPrev && oPrev.RowType === "L" && oPrev.NodeId === oRow.NodeId) {
					aOut.push(Object.assign({}, oRow, {
						DisplayNo: "",
						Description: this._totalLabel(oRow.Description)
					}));
					return;
				}

				aOut.push(oRow);
			}, this);

			return aOut;
		},

		/** The S row closing the run of account rows that starts at iStart. */
		_sectionRowAfter: function (aRows, iStart) {
			var sNodeId = aRows[iStart].NodeId;
			for (var j = iStart + 1; j < aRows.length; j++) {
				if (aRows[j].RowType !== "L" || aRows[j].NodeId !== sNodeId) {
					return aRows[j].RowType === "S" && aRows[j].NodeId === sNodeId ? aRows[j] : null;
				}
			}
			return null;
		},

		_totalLabel: function (sDescription) {
			return this.getView().getModel("i18n").getResourceBundle()
				.getText("sectionTotal", [sDescription || ""]);
		},

		_companyName: function () {
			var sCompanyCode = this.oUiModel.getProperty("/companyCode");
			return COMPANY_NAMES[sCompanyCode] ||
				this.getView().getModel("i18n").getResourceBundle().getText("companyFallback", [sCompanyCode]);
		},

		/* ============================================================
		 * row styling
		 *
		 * sap.ui.table renders a row as up to three separate DOM elements
		 * (frozen part, scrollable part, selector), so bold and fill have
		 * to be applied to each of them. Rows are recycled while
		 * scrolling, which is why the classes are removed and reapplied
		 * on every rowsUpdated rather than set once.
		 * ============================================================ */

		onRowsUpdated: function () {
			var aClasses = ["pnlLeaf", "pnlHeading", "pnlSection", "pnlSubtotal", "pnlMajor"];

			this.byId("pnlTable").getRows().forEach(function (oRow) {
				var aEls = this._rowElements(oRow);
				var oCtx = oRow.getBindingContext("rows");

				aEls.forEach(function (oEl) {
					aClasses.forEach(function (s) {
						oEl.classList.remove(s);
					});

					if (!oCtx) {
						return;
					}

					switch (oCtx.getProperty("RowType")) {
					case "L":
						oEl.classList.add("pnlLeaf");
						break;
					case "H":
						oEl.classList.add("pnlHeading");
						break;
					case "S":
						oEl.classList.add("pnlSection");
						break;
					default:
						oEl.classList.add("pnlSubtotal");
					}

					if (oCtx.getProperty("IsMajorSubtotal") === "X") {
						oEl.classList.add("pnlMajor");
					}
				});
			}.bind(this));
		},

		/**
		 * The DOM elements that make up one table row. Written
		 * defensively: getDomRefs has returned plain elements in some UI5
		 * versions and jQuery collections in others.
		 */
		_rowElements: function (oRow) {
			var aEls = [];

			if (!oRow.getDomRefs) {
				return aEls;
			}

			var oRefs = oRow.getDomRefs(false) || {};
			["rowFixedPart", "rowScrollPart", "rowSelector", "rowAction"].forEach(function (sKey) {
				var vRef = oRefs[sKey];
				if (!vRef) {
					return;
				}
				if (vRef.nodeType) {
					aEls.push(vRef);
				} else if (typeof vRef.length === "number") {
					for (var i = 0; i < vRef.length; i++) {
						if (vRef[i] && vRef[i].nodeType) {
							aEls.push(vRef[i]);
						}
					}
				}
			});

			return aEls;
		},

		/* ============================================================
		 * formatting
		 * ============================================================ */

		/**
		 * Formats one amount for the screen, and must produce exactly what
		 * EXCEL_NUMBER_FORMAT produces in the exported file - acceptance
		 * criterion 6 is that the two agree.
		 *
		 * Deliberately hand-rolled rather than using NumberFormat. The
		 * float instance applied its *short* style here, so 4,824,128 came
		 * out as "5" (meaning 5M) and 268,194 as "268" (268K) - a different
		 * scale per value, which in a P&L is not a cosmetic problem, it is
		 * a wrong number. Grouping with a literal comma also keeps the
		 * screen aligned with the Excel format, which is not locale aware.
		 */
		fmtAmount: function (vValue) {
			if (vValue === null || vValue === undefined || vValue === "") {
				return "";
			}

			// The binding uses targetType:'any', so vValue is the raw OData
			// value - "-4824127.78" or a number - never a formatted string.
			//
			// This guard exists because getting that wrong is dangerous in a
			// way that is invisible. If UI5 formats the value first, and the
			// user's decimal notation is 1.234.567,89, then
			// parseFloat("4.824.127,78") returns 4.824 and this function
			// would render a confident, well-formatted, completely wrong
			// "5". Anything that is not a plain number is echoed through
			// unchanged instead: an ugly cell is a bug you can see.
			if (typeof vValue === "string" && !/^-?\d+(\.\d+)?$/.test(vValue.trim())) {
				return vValue;
			}

			var fValue = parseFloat(vValue);
			if (isNaN(fValue)) {
				return "";
			}

			// Round the magnitude rather than the signed value. Math.round
			// breaks ties towards +Infinity, so -0.5 would become -0 while
			// Excel rounds it away from zero. Taking the absolute value
			// first puts both on the same rule.
			var iValue = Math.round(Math.abs(fValue));

			if (iValue === 0) {
				return "-";
			}

			var sText = String(iValue).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
			return fValue < 0 ? "(" + sText + ")" : sText;
		},

		/* ============================================================
		 * Excel export
		 * ============================================================ */

		onExport: function () {
			var that = this;

			if (!this._validate()) {
				return;
			}

			var oTable = this.byId("pnlTable");
			var oBundle = this.getView().getModel("i18n").getResourceBundle();

			oTable.setBusy(true);

			Promise.all([this._loadExcelJS(), this._fetchAllRows()])
				.then(function (aResult) {
					return that._buildWorkbook(aResult[0], that._withSectionHeadings(aResult[1]));
				})
				.then(function (oBlob) {
					that._download(oBlob, that._fileName());
					MessageToast.show(oBundle.getText("exportDone"));
				})
				.catch(function (oError) {
					MessageBox.error(oBundle.getText("exportFailed") + "\n\n" +
						(oError && oError.message ? oError.message : String(oError)));
				})
				.finally(function () {
					oTable.setBusy(false);
				});
		},

		/**
		 * ExcelJS is bundled in webapp/lib rather than loaded from a CDN -
		 * the S/4HANA Cloud runtime is CSP restricted (FSD 9).
		 */
		_loadExcelJS: function () {
			return new Promise(function (resolve, reject) {
				if (window.ExcelJS) {
					resolve(window.ExcelJS);
					return;
				}
				sap.ui.require(["zfipnl/lib/exceljs.min"], function (oLib) {
					var oExcelJS = oLib || window.ExcelJS;
					if (oExcelJS) {
						resolve(oExcelJS);
					} else {
						reject(new Error("ExcelJS did not load from webapp/lib/exceljs.min.js"));
					}
				}, reject);
			});
		},

		/**
		 * Reads the complete report from the service, page by page, using
		 * its own list binding. The export must contain every row even
		 * when only 20 are on screen (FSD 9). The screen uses it too, since
		 * section headings can only be placed once every row is known.
		 */
		_fetchAllRows: function () {
			var oBinding = this.getView().getModel().bindList(
				ENTITY_SET, null, [], this._buildFilters(), { $count: true });

			var aAll = [];

			function readPage(iStart) {
				return oBinding.requestContexts(iStart, EXPORT_PAGE_SIZE).then(function (aContexts) {
					aContexts.forEach(function (oContext) {
						aAll.push(oContext.getObject());
					});
					if (aContexts.length < EXPORT_PAGE_SIZE) {
						return aAll;
					}
					return readPage(iStart + EXPORT_PAGE_SIZE);
				});
			}

			return readPage(0).finally(function () {
				oBinding.destroy();
			});
		},

		_buildWorkbook: function (ExcelJS, aRows) {
			var oData = this.oUiModel.getData();
			var oBundle = this.getView().getModel("i18n").getResourceBundle();

			var oWorkbook = new ExcelJS.Workbook();
			oWorkbook.created = new Date();
			var oSheet = oWorkbook.addWorksheet("P&L");

			// ---- column widths -------------------------------------
			var aWidths = [42, 14, 30, 16, 16];
			MONTHS.forEach(function () {
				aWidths.push(14);
			});
			oSheet.columns = aWidths.map(function (iWidth) {
				return { width: iWidth };
			});

			// ---- title block ---------------------------------------
			// Company name, report name, then the selection. The fiscal
			// year lives here rather than in the column headers, which
			// stay as plain month names (FSD 9).
			var oCompany = oSheet.getRow(1).getCell(1);
			oCompany.value = this._companyName();
			oCompany.font = { bold: true, size: 14 };

			var oTitle = oSheet.getRow(2).getCell(1);
			oTitle.value = oBundle.getText("excelTitle");
			oTitle.font = { bold: true };

			// With only a Reporting Date the backend derives the fiscal
			// year (2026-10-05 is FY 2027), and returns it on every row.
			var oDataRow = aRows.filter(function (oRow) {
				return oRow.ReportingYear;
			})[0];

			var sSubtitle = oBundle.getText("excelSubtitle", [
				oData.companyCode,
				oData.reportingYear || (oDataRow ? oDataRow.ReportingYear : ""),
				oData.viewMode === "S" ? oBundle.getText("viewSummary") : oBundle.getText("viewDetailed")
			]);
			if (oData.reportingDate) {
				sSubtitle += "   " + oBundle.getText("excelAsAt", [oData.reportingDate]);
			}
			oSheet.getRow(3).getCell(1).value = sSubtitle;

			// ---- header row ----------------------------------------
			var iHeaderRow = 5;
			var aHeaders = [
				oBundle.getText("colDescription"),
				oBundle.getText("excelColGLAccount"),
				oBundle.getText("colGLAccountName"),
				oBundle.getText("colPreviousYear"),
				oBundle.getText("colCurrentYear")
			].concat(MONTHS);

			var oHeader = oSheet.getRow(iHeaderRow);
			aHeaders.forEach(function (sText, i) {
				var oCell = oHeader.getCell(i + 1);
				oCell.value = sText;
				oCell.font = { bold: true };
				oCell.alignment = { horizontal: i < 3 ? "left" : "right", wrapText: true };
				oCell.border = { bottom: { style: "medium" } };
			});

			// ---- data rows -----------------------------------------
			var that = this;
			aRows.forEach(function (oRow, iIndex) {
				var oExcelRow = oSheet.getRow(iHeaderRow + 1 + iIndex);
				var bIsHeading = oRow.RowType === "H";
				var bIsTotal = oRow.RowType === "S" || oRow.RowType === "T";

				// description, indented by level
				var oDesc = oExcelRow.getCell(1);
				oDesc.value = (oRow.DisplayNo ? oRow.DisplayNo + "  " : "") + (oRow.Description || "");
				oDesc.alignment = { indent: Number(oRow.NodeLevel) || 0 };

				oExcelRow.getCell(2).value = oRow.GLAccount || "";
				oExcelRow.getCell(3).value = oRow.GLAccountLongName || "";

				// the 14 amount columns, written as numbers so Excel can
				// still sum them; the display rounding is the cell format.
				// Headings carry no amounts and stay blank, not "-".
				if (!bIsHeading) {
					var aAmounts = [oRow.AmountPreviousYear, oRow.AmountCurrentYear];
					for (var p = 1; p <= 12; p++) {
						aAmounts.push(oRow["AmountPeriod" + (p < 10 ? "0" + p : p)]);
					}
					aAmounts.forEach(function (vAmount, i) {
						var oCell = oExcelRow.getCell(4 + i);
						oCell.value = that._toNumber(vAmount);
						oCell.numFmt = EXCEL_NUMBER_FORMAT;
					});
				}

				if (bIsHeading || bIsTotal) {
					oExcelRow.font = { bold: true };
				}

				if (bIsTotal) {
					oExcelRow.eachCell({ includeEmpty: true }, function (oCell) {
						oCell.border = { top: { style: "thin" } };
					});
				}

				// Headings and totals are shaded across every report column,
				// not just the description. eachCell would stop at the last
				// filled cell, and a heading has no amounts, so loop the
				// columns explicitly.
				var sFill = null;
				if (oRow.IsMajorSubtotal === "X") {
					sFill = EXCEL_FILL_MAJOR;
				} else if (bIsTotal) {
					sFill = EXCEL_FILL_TOTAL;
				} else if (bIsHeading) {
					sFill = EXCEL_FILL_HEADING;
				}
				if (sFill) {
					for (var c = 1; c <= aHeaders.length; c++) {
						oExcelRow.getCell(c).fill = that._excelFill(sFill);
					}
				}
			});

			// ---- filter buttons on the header row ------------------
			oSheet.autoFilter = {
				from: { row: iHeaderRow, column: 1 },
				to: { row: iHeaderRow, column: aHeaders.length }
			};

			// ---- frozen header row and description column ----------
			oSheet.views = [{
				state: "frozen",
				xSplit: 1,
				ySplit: iHeaderRow
			}];

			return oWorkbook.xlsx.writeBuffer().then(function (aBuffer) {
				return new Blob([aBuffer], {
					type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
				});
			});
		},

		_excelFill: function (sArgb) {
			return {
				type: "pattern",
				pattern: "solid",
				fgColor: { argb: sArgb }
			};
		},

		_toNumber: function (vValue) {
			var fValue = parseFloat(vValue);
			return isNaN(fValue) ? 0 : fValue;
		},

		_fileName: function () {
			var oData = this.oUiModel.getData();
			return "PnL_" + oData.companyCode + "_" +
				(oData.reportingDate || oData.reportingYear) + ".xlsx";
		},

		_download: function (oBlob, sFileName) {
			var sUrl = window.URL.createObjectURL(oBlob);
			var oLink = document.createElement("a");
			oLink.href = sUrl;
			oLink.download = sFileName;
			document.body.appendChild(oLink);
			oLink.click();
			document.body.removeChild(oLink);
			window.URL.revokeObjectURL(sUrl);
		}

	});
});
