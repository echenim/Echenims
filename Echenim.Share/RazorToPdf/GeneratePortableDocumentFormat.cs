using iTextSharp.text;
using iTextSharp.text.html;
using iTextSharp.text.pdf;
using iTextSharp.text.xml;
using System;
using System.IO;
using System.Text;
using System.Web;
using System.Web.Mvc;
using System.Xml;

namespace Echenim.Share.RazorToPdf
{
    public class GeneratePortableDocumentFormat : ActionResult
    {


        /// <summary>
        /// method to generate portable document format
        /// </summary>
        /// <param name="viewName">view name</param>
        /// <param name="model">model object or collection</param>
        public GeneratePortableDocumentFormat(string viewName, object model)
        {
            ViewName = viewName;
            Model = model;
        }

        /// <summary>
        /// method to generate portable document format
        /// </summary>
        /// <param name="model">model object or collection</param>
        public GeneratePortableDocumentFormat(object model)
        {
            Model = model;
        }


        /// <summary>
        ///  method to generate portable document format
        /// </summary>
        /// <param name="model">model collectio or object</param>
        /// <param name="configureSettings">configurstion setting</param>
        public GeneratePortableDocumentFormat(object model, Action<PdfWriter, Document> configureSettings)
        {
            if (configureSettings == null)
                throw new ArgumentNullException("configureSettings");
            Model = model;
            ConfigureSettings = configureSettings;
        }

        /// <summary>
        /// method to generate portable document format
        /// </summary>
        /// <param name="viewName">view name</param>
        /// <param name="model">model colectio or object</param>
        /// <param name="configureSettings">config settins</param>
        public GeneratePortableDocumentFormat(string viewName, object model, Action<PdfWriter, Document> configureSettings)
        {
            if (configureSettings == null)
                throw new ArgumentNullException("configureSettings");
            ViewName = viewName;
            Model = model;
            ConfigureSettings = configureSettings;
        }

        public string ViewName { get; set; }
        public object Model { get; set; }
        public Action<PdfWriter, Document> ConfigureSettings { get; set; }

        public string FileDownloadName { get; set; }

        public override void ExecuteResult(ControllerContext context)
        {
            IView viewEngineResult;
            ViewContext viewContext;

            if (ViewName == null)
            {
                ViewName = context.RouteData.GetRequiredString("action");
            }

            context.Controller.ViewData.Model = Model;


            if (context.HttpContext.Request.QueryString["html"] != null &&
                context.HttpContext.Request.QueryString["html"].ToLower().Equals("true"))
            {
                RenderHtmlOutput(context);
            }
            else
            {
                if (!String.IsNullOrEmpty(FileDownloadName))
                {
                    context.HttpContext.Response.AddHeader("content-disposition",
                        "attachment; filename=" + FileDownloadName);
                }

                new FileContentResult(context.GeneratePdf(Model, ViewName, ConfigureSettings), "application/pdf")
                    .ExecuteResult(context);
            }
        }

        private void RenderHtmlOutput(ControllerContext context)
        {
            IView viewEngineResult = ViewEngines.Engines.FindView(context, ViewName, null).View;
            var viewContext = new ViewContext(context, viewEngineResult, context.Controller.ViewData,
                context.Controller.TempData, context.HttpContext.Response.Output);
            viewEngineResult.Render(viewContext, context.HttpContext.Response.Output);
        }
    }
}