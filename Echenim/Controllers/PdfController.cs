using System;
using SysIO = System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using Echenim.Models;
using Echenim.Share.RazorToPdf;

namespace Echenim.Controllers
{
    public class PdfController : Controller
    {

        public ActionResult Index()
        {
            var model = new PdfExample
            {
                Heading = "Heading",
                Items = new List<BasketItem>
                {
                    new BasketItem
                    {
                        Id = 1,
                        Description = "Item 1",
                        Price = 1.99m
                    },
                    new BasketItem
                    {
                        Id = 2,
                        Description = "Item 2",
                        Price = 2.99m
                    }
                }
            };

            return new GeneratePortableDocumentFormat(model);
        }


        public ActionResult SaveTo()
        {
            var model = new PdfExample
            {
                Heading = "Heading",
                Items = new List<BasketItem>
                {
                    new BasketItem
                    {
                        Id = 1,
                        Description = "Item 1",
                        Price = 1.99m
                    },
                    new BasketItem
                    {
                        Id = 2,
                        Description = "Item 2",
                        Price = 2.99m
                    }
                }
            };

            byte[] pdfOutput = ControllerContext.GeneratePdf(model, "DocumentAndWriter");
            string fullPath = Server.MapPath("~/DFreshlyMade.pdf");

            if (SysIO.File.Exists(fullPath))
            {
                SysIO.File.Delete(fullPath);
            }
            SysIO.File.WriteAllBytes(fullPath, pdfOutput);

            return View("SaveTo");
        }

        //public ActionResult DocumentAndWriter()
        //{
        //    var model = new PdfExample
        //    {
        //        Heading = "Heading",
        //        Items = new List<BasketItem>
        //        {
        //            new BasketItem
        //            {
        //                Id = 1,
        //                Description = "Item 1",
        //                Price = 1.99m
        //            },
        //            new BasketItem
        //            {
        //                Id = 2,
        //                Description = "Item 2",
        //                Price = 2.99m
        //            }
        //        }
        //    };

        //    return new GeneratePortableDocumentFormat(model, (writer, document) =>
        //    {
        //        document.SetPageSize(new Rectangle(500f, 500f, 90));
        //        document.NewPage();
        //    });
        //}


        //public ActionResult DocumentAndWriterDownloadFile()
        //{
        //    var model = new PdfExample
        //    {
        //        Heading = "Heading",
        //        Items = new List<BasketItem>
        //        {
        //            new BasketItem
        //            {
        //                Id = 1,
        //                Description = "Item 1",
        //                Price = 1.99m
        //            },
        //            new BasketItem
        //            {
        //                Id = 2,
        //                Description = "Item 2",
        //                Price = 2.99m
        //            }
        //        }
        //    };

        //    return new GeneratePortableDocumentFormat(model, (writer, document) =>
        //    {
        //        document.SetPageSize(new Rectangle(500f, 500f, 90));
        //        document.NewPage();
        //    })
        //    {
        //        FileDownloadName = "download.pdf"
        //    };
        //}

    }
}