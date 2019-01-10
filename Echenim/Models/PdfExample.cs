using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace Echenim.Models
{
    public class PdfExample
    {
        public string Heading { get; set; }
        public IEnumerable<BasketItem> Items { get; set; }
    }
}