// Plumbline Council Runner -- browser client.
//
// POSTs {subject, preset, mode} to /run and renders the returned envelope. ALL
// rendering uses textContent (never innerHTML of untrusted content), so a pasted
// subject or a council position can never inject markup or script. The browser
// never holds or sees the provider secret -- the secret is resident only in the
// proxy process and flows only to the spawned child. This view never presents a
// verdict or approval; it shows REAL positions (from a live run), the diversity
// block, and the RISK-B-007 "no verdict" disclosure honestly.
//
// NO DEMO: there is no bundled/fabricated council anywhere. When live is not
// enabled the server returns a classified COUNCIL_LIVE_REQUIRED message, which is
// shown honestly -- never a fake sample.

(function () {
  "use strict";

  var DISCLOSURE_RISK = "RISK-B-007";

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) { node.className = cls; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }

  function setStatus(msg) {
    document.getElementById("status").textContent = msg;
  }

  // Honest LIVE-status / attrition indicator: when some roles were rate-limited or
  // unavailable, say so explicitly so the operator is never misled into reading a
  // partial council as a complete one.
  function setAttrition(council) {
    var box = document.getElementById("attrition");
    box.textContent = "";
    box.hidden = true;
    if (!council || !council.positions) { return; }
    var positions = council.positions;
    var down = [];
    for (var i = 0; i < positions.length; i++) {
      var p = positions[i];
      if (p.position === null || p.position === undefined) {
        down.push((p.role || "?") + " (" + (p.code || "unavailable") + ")");
      }
    }
    if (down.length === 0) { return; }
    box.hidden = false;
    box.appendChild(el(
      "p",
      "attrition-line",
      down.length + " of " + positions.length +
        " council roles were unavailable (rate-limited / model unavailable on the " +
        "free tier): " + down.join(", ") + ". Their absence is shown honestly; no " +
        "position was fabricated for them."
    ));
  }

  function renderCouncil(results, council, subject) {
    var section = el("section", "council");
    section.appendChild(el("p", "subject", "Subject: " + subject));
    section.appendChild(el("p", "overall", "Overall: " + (council.code || "")));

    var list = el("ul", "positions");
    var positions = council.positions || [];
    for (var i = 0; i < positions.length; i++) {
      var pos = positions[i];
      var item = el("li", "position");
      item.appendChild(el("span", "role", pos.role));
      item.appendChild(el("span", "model", pos.model));
      // Honest mixed render: an OK role shows its position; a non-OK role shows
      // its EXACT classified code. Never collapse to a single error banner.
      if (pos.position !== null && pos.position !== undefined) {
        item.appendChild(el("span", "text", pos.position));
      } else {
        item.appendChild(el("span", "code", pos.code));
      }
      list.appendChild(item);
    }
    section.appendChild(list);

    var diversity = council.diversity || {};
    var divBlock = el("section", "diversity");
    divBlock.appendChild(el("p", "distinct", "distinct_bases: " + diversity.distinct_bases));
    divBlock.appendChild(el("p", "gate", "gate: " + diversity.gate));
    var disclosure = diversity.disclosure || "";
    if (disclosure.indexOf(DISCLOSURE_RISK) === -1) {
      disclosure = disclosure + " (" + DISCLOSURE_RISK + ")";
    }
    divBlock.appendChild(el("p", "disclosure", disclosure));
    section.appendChild(divBlock);

    results.appendChild(section);
  }

  function renderError(results, code, message) {
    var section = el("section", "error");
    section.appendChild(el("p", "code", code || "error"));
    section.appendChild(el("p", "message", message || ""));
    results.appendChild(section);
  }

  function render(envelope, subject) {
    var results = document.getElementById("results");
    results.textContent = "";
    setAttrition(envelope.council);
    if (envelope.council) {
      renderCouncil(results, envelope.council, subject);
    } else {
      // No council: surface the EXACT classified code and the server's honest,
      // actionable message (e.g. "enable live to run the council"). No fake sample.
      var msg = envelope.message ||
        "the council run did not return positions";
      renderError(results, envelope.error_code, msg);
    }
  }

  function onSubmit(event) {
    event.preventDefault();
    var subject = document.getElementById("subject").value;
    var preset = document.getElementById("preset").value;
    var mode = document.getElementById("mode").value;
    setStatus("Running the real council...");
    fetch("/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ subject: subject, preset: preset, mode: mode })
    }).then(function (resp) {
      return resp.json();
    }).then(function (envelope) {
      if (envelope.refused) {
        setStatus("Live run refused: " + (envelope.error_code || ""));
      } else if (envelope.status >= 400) {
        setStatus("Error: " + (envelope.error_code || envelope.status));
      } else {
        setStatus("");
      }
      render(envelope, subject);
    }).catch(function () {
      setStatus("Request failed.");
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.getElementById("run-form").addEventListener("submit", onSubmit);
  });
}());
