using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Web.Mvc;
using System.Xml;
using iTextSharp.text;
using iTextSharp.text.html;
using iTextSharp.text.pdf;
using iTextSharp.text.xml;

namespace Echenim.Share.RazorToPdf
{
    public static class RazorToPdfExtensions
    {
        public static byte[] GeneratePdf(this ControllerContext context, object model = null, string viewName = null,
            Action<PdfWriter, Document> configureSettings = null) => new RazorToPdf().GeneratePdfOutput(context, model, viewName, configureSettings);
    }

}
