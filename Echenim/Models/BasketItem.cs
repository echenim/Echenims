﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace Echenim.Models
{
    public class BasketItem
    {
        public int Id { get; set; }
        public string Description { get; set; }
        public decimal Price { get; set; }
    }
}